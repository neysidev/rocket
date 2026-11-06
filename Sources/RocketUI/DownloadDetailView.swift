import AppKit
import Charts
import RocketCore
import RocketDesign
import SwiftUI

/// Inspector for one download (FR-APP-02): a header bar with Close and icon-only actions, a progress ring with the
/// numbers that matter, full-width speed chart and connection map while running, then source and destination.
/// Everything else (URL, ETag, dates, log) sits in collapsed disclosures.
public struct DownloadDetailView: View {
    let model: DownloadsModel
    let id: UUID
    @State private var details: DownloadDetails?
    @State private var showsInfo = false
    @State private var showsLog = false

    public init(model: DownloadsModel, id: UUID) {
        self.model = model
        self.id = id
    }

    private var item: DownloadItem? { model.items.first { $0.id == id } }

    public var body: some View {
        Group {
            if let item {
                form(item)
            } else {
                ContentUnavailableView("Download Removed", systemImage: "tray")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .task(id: id) {
            // 2 Hz is plenty for segments and the log; progress numbers come from the list's 5 Hz snapshot.
            while !Task.isCancelled {
                details = await model.details(id)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { model.detailsID = nil } label: { Label("Close", systemImage: "xmark") }
                .keyboardShortcut(.cancelAction)
                .help("Close Details (Esc)")
            Spacer()
            if let download = item?.download {
                ForEach(actions(for: download), id: \.self) { action in
                    Button { action.perform(on: download, model: model) } label: { Label(action.title, systemImage: action.symbol) }
                        .help(action.title)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(download.url.absoluteString, forType: .string)
                } label: { Label("Copy Link", systemImage: "link") }
                    .help("Copy Link")
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func actions(for download: Download) -> [RowAction] {
        RowAction.available(for: download).filter { ![.details, .viewError, .remove].contains($0) }
    }

    // MARK: Content

    private func form(_ item: DownloadItem) -> some View {
        let download = item.download
        return Form {
            Section { Summary(item: item) }
            if download.state == .failed, let failure = download.failure {
                Section {
                    Label(failure.userMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let samples = model.speedSamples[id], samples.contains(where: { $0 > 0 }) {
                Section("Speed") { SpeedChart(samples: samples) }
            }
            if let segments = details?.segments, !segments.isEmpty, download.state != .completed {
                Section("Connections") {
                    SegmentsBar(segments: segments, total: download.totalBytes, live: download.state == .downloading)
                    Text(connectionText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Source", value: DownloadSource.host(for: download.url))
                LabeledContent("Saved to") {
                    Button(savedFolder(download)) { model.reveal([download.id]) }
                        .buttonStyle(.link)
                        .help("Show in Finder")
                }
                DisclosureGroup("More Info", isExpanded: $showsInfo) { info(download) }
                if let log = details?.log, !log.isEmpty {
                    DisclosureGroup("Activity Log", isExpanded: $showsLog) { LogList(entries: log) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func savedFolder(_ download: Download) -> String {
        URL(filePath: download.destinationPath).lastPathComponent
    }

    private var connectionText: String {
        let count = details?.segments.count ?? 0
        guard let details, let limit = details.connectionLimit else { return String(localized: "\(count) segments") }
        return String(localized: "\(details.activeConnections) of \(limit) connections active · \(count) segments")
    }

    @ViewBuilder
    private func info(_ download: Download) -> some View {
        row("URL", download.url.absoluteString, copyable: true)
        if let final = download.finalURL, final != download.url { row("Redirected to", final.absoluteString, copyable: true) }
        row("Path", download.state == .completed ? download.fileURL.path : download.destinationPath)
        row("Queue", model.queues.first { $0.id == download.queueID }?.name ?? download.queueID)
        row("Resumable", download.acceptsRanges ? String(localized: "Yes") : String(localized: "No, single connection"))
        if let limit = download.speedLimit { row("Speed limit", Format.speed(Double(limit))) }
        if let etag = download.etag { row("ETag", etag) }
        if let modified = download.lastModified { row("Last modified", modified) }
        row("Added", download.createdAt.formatted(date: .abbreviated, time: .shortened))
        if let completed = download.completedAt { row("Completed", completed.formatted(date: .abbreviated, time: .shortened)) }
    }

    private func row(_ label: LocalizedStringKey, _ value: String, copyable: Bool = false) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(value)
                if copyable {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .help("Copy")
                }
            }
        }
    }
}

/// Progress ring around the file icon, then name, status, bytes, and live speed with time left.
private struct Summary: View {
    let item: DownloadItem

    private var download: Download { item.download }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: ringFraction)
                FileThumbnail(item: item, size: 30)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(download.fileName)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    StatusGlyph(download.state.glyph(item.fraction), size: 11)
                    Text(statusText).foregroundStyle(tint)
                }
                .font(.callout)
                Text(bytesText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if download.state == .downloading, item.speed > 0 {
                    Text([Format.speed(item.speed), item.secondsLeft.map(Format.timeLeft)].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var ringFraction: Double {
        download.state == .completed ? 1 : min(1, max(0, item.fraction ?? 0))
    }

    private var tint: Color {
        switch download.state {
        case .completed: RocketColor.success
        case .failed: RocketColor.danger
        case .paused, .queued, .cancelled: RocketColor.textSecondary
        case .probing, .downloading, .verifying: RocketColor.accent
        }
    }

    private var statusText: String {
        guard download.state != .completed, let fraction = item.fraction else { return download.state.title }
        return "\(download.state.title) · \(fraction.formatted(.percent.precision(.fractionLength(0))))"
    }

    private var bytesText: String {
        let received = Format.bytes(download.receivedBytes)
        guard let total = download.totalBytes else { return received }
        return download.state == .completed ? Format.bytes(total) : String(localized: "\(received) of \(Format.bytes(total))")
    }
}

/// One track split into per-connection ranges, 1 pt apart; each fills as its connection receives bytes.
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
                                .fill(segment.isComplete ? RocketColor.success : live ? RocketColor.accent : RocketColor.textTertiary)
                                .frame(width: width * min(1, Double(segment.received) / length))
                        }
                        .frame(width: width)
                }
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "\(segments.count) segments, \(segments.count(where: \.isComplete)) finished"))
    }
}

/// Full-width speed over the last minute: area under a line, with current, average and peak below.
struct SpeedChart: View {
    let samples: [Double]

    var body: some View {
        let peak = samples.max() ?? 0
        let moving = samples.filter { $0 > 0 }
        let average = moving.isEmpty ? 0 : moving.reduce(0, +) / Double(moving.count)
        VStack(alignment: .leading, spacing: 8) {
            Chart(Array(samples.enumerated()), id: \.offset) { index, speed in
                AreaMark(x: .value("Time", index), y: .value("Speed", speed))
                    .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", index), y: .value("Speed", speed))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXScale(domain: 0...max(1, samples.count - 1))
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            HStack {
                stat("Now", samples.last ?? 0)
                Spacer()
                stat("Average", average)
                Spacer()
                stat("Peak", peak)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Speed over the last minute, peak \(Format.speed(peak))"))
    }

    private func stat(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Format.speed(value)).font(.callout.weight(.medium)).monospacedDigit()
        }
    }
}

struct LogList: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entries.suffix(50).reversed().enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.tertiary)
                    Text(entry.message)
                        .foregroundStyle(entry.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
