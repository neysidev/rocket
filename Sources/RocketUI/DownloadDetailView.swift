import AppKit
import Charts
import RocketCore
import RocketDesign
import SwiftUI

/// Details for one download, shown in a modal: metrics, live segments, speed history, server details, errors and log (FR-APP-02).
public struct DownloadDetailView: View {
    let model: DownloadsModel
    let id: UUID
    @State private var details: DownloadDetails?
    @Environment(\.rocketDismiss) private var dismiss

    public init(model: DownloadsModel, id: UUID) {
        self.model = model
        self.id = id
    }

    private var item: DownloadItem? { model.items.first { $0.id == id } }

    public var body: some View {
        VStack(spacing: 0) {
            if let item {
                header(item)
                ScrollView {
                    VStack(alignment: .leading, spacing: RocketSpace.s6) {
                        metrics(item)
                        if let failure = item.download.failure {
                            HStack(alignment: .firstTextBaseline, spacing: RocketSpace.s3) {
                                StatusGlyph(.failed, size: 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                                Text(failure.userMessage)
                                    .font(.rocketBody)
                                    .foregroundStyle(RocketColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(RocketSpace.s4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(item.download.state == .failed ? RocketColor.dangerSoft : RocketColor.control,
                                        in: RoundedRectangle(cornerRadius: RocketRadius.card, style: .continuous))
                        }
                        if let segments = details?.segments, !segments.isEmpty, item.download.state != .completed {
                            section("Connections") {
                                SegmentsBar(segments: segments, total: item.download.totalBytes, live: item.download.state == .downloading)
                                Text(connectionText(item))
                                    .font(.rocketCaption)
                                    .foregroundStyle(RocketColor.textTertiary)
                            }
                        }
                        if let samples = model.speedSamples[id], samples.contains(where: { $0 > 0 }) {
                            section("Speed, last minute") { SpeedChart(samples: samples) }
                        }
                        section("Details") { info(item.download) }
                        if let log = details?.log, !log.isEmpty {
                            section("Log") { LogList(entries: log) }
                        }
                    }
                    .padding(RocketSpace.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Grows with its content (the log), then scrolls.
                .frame(maxHeight: 560)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This download was removed.")
                    .font(.rocketBody)
                    .foregroundStyle(RocketColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: id) {
            // 2 Hz is plenty for segments and the log; progress numbers come from the list's 5 Hz snapshot.
            while !Task.isCancelled {
                details = await model.details(id)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func header(_ item: DownloadItem) -> some View {
        HStack(spacing: RocketSpace.s4) {
            FileThumbnail(item: item, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.download.fileName)
                    .font(.rocketTitle)
                    .foregroundStyle(RocketColor.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                StatusLabel(item: item, showsDetail: false)
            }
            Spacer(minLength: RocketSpace.s3)
            HStack(spacing: RocketSpace.s1) {
                ForEach(RowAction.available(for: item.download).filter { ![.details, .viewError, .remove].contains($0) }, id: \.self) { action in
                    Button(action.title, systemImage: action.symbol) { action.perform(on: item.download, model: model) }
                        .buttonStyle(IconButtonStyle(role: action == .cancel ? .destructive : nil))
                        .rocketTooltip(action.title)
                }
                Rectangle().fill(RocketColor.border).frame(width: 1, height: 16).padding(.horizontal, RocketSpace.s2)
                Button("Close", systemImage: "xmark") { dismiss() }
                    .buttonStyle(.rocketIcon)
                    .keyboardShortcut(.cancelAction)
                    .rocketTooltip(String(localized: "Close"), shortcut: "esc")
            }
        }
        .padding(.horizontal, RocketSpace.s6)
        .padding(.vertical, RocketSpace.s5)
        .overlay(alignment: .bottom) { Rectangle().fill(RocketColor.border).frame(height: 1) }
    }

    private func metrics(_ item: DownloadItem) -> some View {
        HStack(spacing: RocketSpace.s3) {
            metric(Format.bytes(item.download.receivedBytes), caption: item.download.totalBytes.map { "of \(Format.bytes($0))" } ?? "received")
            if item.download.state == .downloading {
                let (value, unit) = Format.compactSpeed(item.speed)
                metric("\(value) \(unit)", caption: item.secondsLeft.map(Format.timeLeft) ?? "speed", live: true)
            }
            if let fraction = item.fraction, item.download.state != .completed {
                metric(fraction.formatted(.percent.precision(.fractionLength(0))), caption: "complete")
            }
        }
    }

    private func metric(_ value: String, caption: String, live: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: RocketSpace.s1) {
            Text(value)
                .font(.rocketMetric)
                .foregroundStyle(live ? RocketColor.accentText : RocketColor.textPrimary)
                .contentTransition(.numericText())
            Text(caption).font(.rocketLabel).foregroundStyle(RocketColor.textSecondary)
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rocketCard()
    }

    private func connectionText(_ item: DownloadItem) -> String {
        let count = details?.segments.count ?? 0
        guard let details, details.connectionLimit != nil else { return String(localized: "\(count) segments") }
        return String(localized: "\(details.activeConnections) of \(details.connectionLimit ?? 0) connections active · \(count) segments")
    }

    private func info(_ download: Download) -> some View {
        VStack(spacing: 0) {
            row("URL", download.url.absoluteString, mono: true, copyable: true)
            if let final = download.finalURL, final != download.url { row("Redirected to", final.absoluteString, mono: true, copyable: true) }
            row("Saved to", download.state == .completed ? download.fileURL.path : download.destinationPath, mono: true)
            row("Queue", model.queues.first { $0.id == download.queueID }?.name ?? download.queueID)
            row("Resumable", download.acceptsRanges ? String(localized: "Yes") : String(localized: "No, single connection"))
            if let limit = download.speedLimit { row("Speed limit", Format.speed(Double(limit))) }
            if let etag = download.etag { row("ETag", etag, mono: true) }
            if let modified = download.lastModified { row("Last modified", modified) }
            row("Added", download.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let completed = download.completedAt { row("Completed", completed.formatted(date: .abbreviated, time: .shortened)) }
        }
        .padding(.bottom, -1)
        .clipShape(RoundedRectangle(cornerRadius: RocketRadius.card, style: .continuous))
        .rocketCard()
    }

    private func row(_ label: LocalizedStringKey, _ value: String, mono: Bool = false, copyable: Bool = false) -> some View {
        HStack(spacing: RocketSpace.s4) {
            Text(label)
                .font(.rocketLabel)
                .foregroundStyle(RocketColor.textSecondary)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(mono ? .rocketMono : .rocketBody)
                .foregroundStyle(RocketColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rocketTooltip(value)
            if copyable {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .buttonStyle(IconButtonStyle(size: 22))
                .rocketTooltip(String(localized: "Copy"))
            }
        }
        .padding(.horizontal, RocketSpace.s4)
        .frame(minHeight: 36)
        .overlay(alignment: .bottom) { Rectangle().fill(RocketColor.border).frame(height: 1) }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            Text(title).rocketEyebrow()
            content()
        }
    }
}

/// One 6 pt track split into per-connection ranges, 1 pt apart; each fills as its connection receives bytes.
struct SegmentsBar: View {
    let segments: [Segment]
    let total: Int64?
    let live: Bool

    var body: some View {
        let ordered = segments.sorted { $0.start < $1.start }
        let size = Double(total ?? ordered.last.map { $0.end + 1 } ?? 1)
        GeometryReader { proxy in
            let usable = proxy.size.width - CGFloat(max(0, ordered.count - 1))
            HStack(spacing: 1) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, segment in
                    let length = Double(segment.end - segment.start + 1)
                    let width = max(1, usable * length / size)
                    Capsule()
                        .fill(RocketColor.track)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(segment.isComplete ? RocketColor.success.opacity(0.6) : live ? RocketColor.accent : RocketColor.textTertiary)
                                .frame(width: width * min(1, Double(segment.received) / length))
                        }
                        .frame(width: width)
                }
            }
        }
        .frame(height: RocketSize.progressBarDetail)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "\(segments.count) segments, \(segments.count(where: \.isComplete)) finished"))
    }
}

/// 60-second line in Ember, 1.5 pt, 12 % area fill, no gridlines, one caption for the peak.
struct SpeedChart: View {
    let samples: [Double]

    var body: some View {
        let peak = samples.max() ?? 0
        VStack(alignment: .leading, spacing: RocketSpace.s1) {
            Chart(Array(samples.enumerated()), id: \.offset) { index, speed in
                AreaMark(x: .value("Time", index), y: .value("Speed", speed))
                    .foregroundStyle(RocketColor.accent.opacity(0.12))
                LineMark(x: .value("Time", index), y: .value("Speed", speed))
                    .foregroundStyle(RocketColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXScale(domain: 0...299)
            .frame(height: 64)
            Text("Peak \(Format.speed(peak))")
                .font(.rocketCaption)
                .foregroundStyle(RocketColor.textTertiary)
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Speed over the last minute, peak \(Format.speed(peak))"))
    }
}

struct LogList: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s2) {
            ForEach(Array(entries.suffix(50).reversed().enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: RocketSpace.s3) {
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(RocketColor.textTertiary)
                    Text(entry.message)
                        .foregroundStyle(entry.isError ? RocketColor.danger : RocketColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.rocketMono)
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rocketCard(fill: RocketColor.control.opacity(0.5))
        .textSelection(.enabled)
    }
}
