import AppKit
import Charts
import RocketCore
import RocketDesign
import SwiftUI

/// Inspector for one download (FR-APP-02), adapted to its state:
/// 1. Download Details — icon, name, status, size and the actions that matter right now (Open / Show in Finder when done).
/// 2. A state section — live speed and connections while running, progress and resume info when paused, the error and
///    recovery when failed. Nothing live is shown for finished downloads.
/// 3. File Information — where it is, where it came from, when.
/// 4. Technical Details and Activity Log — collapsed by default; their open state is remembered.
public struct DownloadDetailView: View {
    let model: DownloadsModel
    let id: UUID
    @State private var details: DownloadDetails?
    @AppStorage("inspector.showsTechnical") private var showsTechnical = false
    @AppStorage("inspector.showsLog") private var showsLog = false

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
            details = nil
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
            Text("Inspector")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if let download = item?.download {
                Button { copy(download.url.absoluteString) } label: { Label("Copy Link", systemImage: "link") }
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

    // MARK: Content

    private func form(_ item: DownloadItem) -> some View {
        let download = item.download
        return Form {
            Section {
                Summary(item: item)
                ActionBar(actions: primaryActions(for: download)) { $0.perform(on: download, model: model) }
            }
            stateSection(item)
            Section("File Information") { fileInfo(download) }
            Section {
                DisclosureGroup("Technical Details", isExpanded: $showsTechnical) { technical(download) }
                DisclosureGroup(isExpanded: $showsLog) {
                    if let log = details?.log, !log.isEmpty {
                        LogList(entries: log)
                    } else {
                        Text(details == nil ? "Loading…" : "No activity recorded yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack {
                        Text("Activity Log")
                        Spacer()
                        if let count = details?.log.count, count > 0 {
                            Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .animation(.easeOut(duration: 0.2), value: download.state)
    }

    /// Open + Show in Finder once finished; otherwise the lifecycle actions for this state, then Show in Finder
    /// when a partial file exists.
    private func primaryActions(for download: Download) -> [RowAction] {
        var actions = RowAction.available(for: download).filter { ![.details, .viewError, .remove].contains($0) }
        if download.state != .completed, download.receivedBytes > 0, !actions.contains(.reveal) { actions.append(.reveal) }
        return actions
    }

    // MARK: State section

    @ViewBuilder
    private func stateSection(_ item: DownloadItem) -> some View {
        let download = item.download
        switch download.state {
        case .probing, .downloading, .verifying:
            Section("Transfer") {
                if let samples = model.speedSamples[id], samples.contains(where: { $0 > 0 }) {
                    SpeedChart(samples: samples)
                }
                if let left = item.secondsLeft, download.state == .downloading {
                    LabeledContent("Time left", value: Format.timeLeft(left))
                }
                connections(download, live: download.state == .downloading)
            }
        case .paused:
            Section("Paused") {
                progress(item)
                LabeledContent("On resume") {
                    Text(download.acceptsRanges
                         ? String(localized: "Continues from \(Format.bytes(download.receivedBytes))")
                         : String(localized: "Restarts from the beginning"))
                }
                if !download.acceptsRanges {
                    Text("This server doesn't support resuming, so progress will be lost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                connections(download, live: false)
            }
        case .queued:
            if download.receivedBytes > 0 { Section("Progress") { progress(item) } }
        case .failed:
            Section("Problem") {
                if let failure = download.failure {
                    Label(failure.userMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(RocketColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recoveryHint(failure))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("The download stopped without a reported reason.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(RocketColor.danger)
                }
                if download.receivedBytes > 0 { progress(item) }
            }
        case .completed, .cancelled:
            EmptyView()
        }
    }

    private func progress(_ item: DownloadItem) -> some View {
        let download = item.download
        return VStack(alignment: .leading, spacing: 6) {
            if let fraction = item.fraction {
                ProgressView(value: min(1, max(0, fraction)))
                    .tint(download.state == .failed ? RocketColor.danger : RocketColor.textSecondary)
            }
            HStack {
                Text(download.totalBytes.map { String(localized: "\(Format.bytes(download.receivedBytes)) of \(Format.bytes($0))") }
                     ?? Format.bytes(download.receivedBytes))
                Spacer()
                if let fraction = item.fraction { Text(fraction.formatted(.percent.precision(.fractionLength(0)))) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func connections(_ download: Download, live: Bool) -> some View {
        if let segments = details?.segments, !segments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SegmentsBar(segments: segments, total: download.totalBytes, live: live)
                Text(connectionText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var connectionText: String {
        let count = details?.segments.count ?? 0
        guard let details, let limit = details.connectionLimit else { return String(localized: "\(count) segments") }
        return String(localized: "\(details.activeConnections) of \(limit) connections active · \(count) segments")
    }

    private func recoveryHint(_ failure: DownloadError) -> String {
        if case .http(let status) = failure, [401, 403, 404, 410].contains(status) {
            return String(localized: "The link may have expired. Use Refresh Link to point the download at a new URL.")
        }
        return switch failure.kind {
        case .transient: String(localized: "This is usually temporary. Retry to try again.")
        case .needsUser: String(localized: "Fix the problem above, then retry.")
        case .fatal: String(localized: "Retrying with the same link is unlikely to help.")
        }
    }

    // MARK: File Information

    @ViewBuilder
    private func fileInfo(_ download: Download) -> some View {
        LabeledContent("Saved to") {
            Button(URL(filePath: download.destinationPath).lastPathComponent) { model.reveal([download.id]) }
                .buttonStyle(.link)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(download.destinationPath)
        }
        row("Source", DownloadSource.host(for: download.url))
        row("Size", download.totalBytes.map(Format.bytes) ?? String(localized: "Unknown"))
        row("Added", download.createdAt.formatted(date: .abbreviated, time: .shortened))
        if let completed = download.completedAt {
            row("Completed", completed.formatted(date: .abbreviated, time: .shortened))
        }
        row("Resumable", download.acceptsRanges ? String(localized: "Yes") : String(localized: "No"))
    }

    // MARK: Technical Details

    @ViewBuilder
    private func technical(_ download: Download) -> some View {
        row("URL", download.url.absoluteString, copyable: true)
        if let final = download.finalURL, final != download.url { row("Redirected to", final.absoluteString, copyable: true) }
        row("Path", download.state == .completed ? download.fileURL.path : download.partFileURL.path, copyable: true)
        row("Range requests", download.acceptsRanges
            ? String(localized: "Supported, up to \(download.connections) connections")
            : String(localized: "Not supported, single connection"))
        row("ETag", download.etag ?? String(localized: "Not provided"), copyable: download.etag != nil)
        row("Last modified", download.lastModified ?? String(localized: "Not provided"))
        if let checksum = download.expectedChecksum {
            row("\(checksum.algorithm.title)", checksum.value, copyable: true)
        }
        row("Queue", model.queues.first { $0.id == download.queueID }?.name ?? download.queueID)
        if let limit = download.speedLimit { row("Speed limit", Format.speed(Double(limit))) }
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
                    Button { copy(value) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .help("Copy")
                }
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

/// The state's actions as full-width buttons; the first one is the default.
private struct ActionBar: View {
    let actions: [RowAction]
    let perform: (RowAction) -> Void

    var body: some View {
        if !actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                    let button = Button { perform(action) } label: {
                        Label(action.title, systemImage: action.symbol).frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help(action.title)
                    if index == 0 { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
                }
            }
            .labelStyle(.titleOnly)
            .lineLimit(1)
        }
    }
}

/// Progress ring around the file icon (only while unfinished), then name, status and size.
private struct Summary: View {
    let item: DownloadItem

    private var download: Download { item.download }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if download.state != .completed {
                    Circle().stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: ringFraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: ringFraction)
                }
                FileThumbnail(item: item, size: download.state == .completed ? 40 : 30)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(download.fileName)
                    .font(.headline)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(download.fileName)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var ringFraction: Double { min(1, max(0, item.fraction ?? 0)) }

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
        guard let total = download.totalBytes else {
            return download.state == .completed ? received : String(localized: "\(received) of unknown size")
        }
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
