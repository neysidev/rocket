import AppKit
import RocketCore
import RocketDesign
import SwiftUI

/// One small native window per download: opens when a new download starts and follows it through
/// waiting, transferring, verifying, and the final completed / failed / cancelled state.
@MainActor
public final class DownloadWindows: NSObject, NSWindowDelegate {
    private let model: DownloadsModel
    private var windows: [UUID: NSWindow] = [:]
    /// Closed by the user; never reopened automatically this session.
    private var dismissed: Set<UUID> = []
    /// Only downloads added after launch open a window, so relaunching with work in flight stays quiet.
    private let launch = Date.now

    public init(model: DownloadsModel) {
        self.model = model
    }

    /// Call after every model update.
    public func update(enabled: Bool) {
        let ids = Set(model.items.map(\.id))
        for (id, window) in windows where !ids.contains(id) { window.close() }
        guard enabled else { return }
        for item in model.items where item.download.state.isTransferring && item.download.createdAt >= launch
            && windows[item.id] == nil && !dismissed.contains(item.id) {
            show(item.id, activate: false)
        }
    }

    /// Opens (or brings forward) the window for `id`.
    public func show(_ id: UUID, activate: Bool = true) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            if activate { NSApp.activate() }
            return
        }
        guard let download = model.download(id) else { return }
        let host = NSHostingController(rootView: DownloadWindowView(model: model, id: id, close: { [weak self] in
            self?.windows[id]?.close()
        }, fit: { [weak self] in
            self?.fit(id)
        }))
        // No automatic sizing: the view keeps one height in every state, so size the window once.
        // (Live preferredContentSize sizing loops AppKit's constraint pass and crashes.)
        host.sizingOptions = []
        // Alert-style panel: file name as the title, no minimize/zoom, movable by its background, Esc closes it.
        // A panel would normally hide when Rocket isn't frontmost; this one stays, since downloads start from the browser.
        let window = NSPanel(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.title = download.fileName
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        window.setContentSize(host.view.fittingSize)
        window.center()
        // Cascade so several downloads don't stack exactly on top of each other.
        let offset = CGFloat(windows.count % 8) * 24
        window.setFrameOrigin(NSPoint(x: window.frame.minX + offset, y: window.frame.minY - offset))
        windows[id] = window
        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            // Appears over the browser that started the download without stealing focus.
            window.orderFrontRegardless()
        }
    }

    /// Re-fits the height after a state change (e.g. a two-line error), keeping the top edge in place.
    /// Done once per change on the next run-loop turn; continuous auto-sizing loops AppKit's constraint pass.
    private func fit(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.windows[id], let view = window.contentView,
                  let host = window.contentViewController as? NSHostingController<DownloadWindowView> else { return }
            // Ask SwiftUI directly; `fittingSize` can come back near zero mid-update and collapse the window.
            let size = host.sizeThatFits(in: NSSize(width: view.frame.width, height: .greatestFiniteMagnitude))
            guard size.height >= 100, abs(size.height - view.frame.height) > 0.5 else { return }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: view.frame.width, height: size.height)))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true, animate: true)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
        dismissed.insert(id)
    }
}


/// The file name lives in the native title bar; below it, the icon sits beside the status and percentage,
/// one progress bar, and one line with size, speed and time left, followed by equal-width alert buttons.
struct DownloadWindowView: View {
    let model: DownloadsModel
    let id: UUID
    let close: () -> Void
    /// Asks the window to re-fit its height.
    let fit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase: Equatable {
        case queued, connecting, transferring, paused, verifying, completed, failed, cancelled

        init(_ state: DownloadState) {
            switch state {
            case .queued: self = .queued
            case .probing: self = .connecting
            case .downloading: self = .transferring
            case .paused: self = .paused
            case .verifying: self = .verifying
            case .completed: self = .completed
            case .failed: self = .failed
            case .cancelled: self = .cancelled
            }
        }
    }

    var body: some View {
        if let item = model.items.first(where: { $0.id == id }) {
            content(item)
        }
    }

    private func content(_ item: DownloadItem) -> some View {
        let phase = Phase(item.download.state)
        return VStack(spacing: 22) {
            HStack(alignment: .center, spacing: 16) {
                FileThumbnail(item: item, size: 56)
                    .overlay(alignment: .bottomTrailing) { badge(phase).offset(x: 5, y: 5) }
                VStack(alignment: .leading, spacing: 8) {
                    statusLine(item, phase: phase)
                    bar(item, phase: phase)
                    infoLine(item, phase: phase)
                        .id(phase == .failed)
                        .transition(.opacity)
                }
            }
            HStack(spacing: 8) { buttons(item, phase: phase) }
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(width: 440)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: phase)
        .onChange(of: phase) { fit() }
    }

    // MARK: Status

    private func statusLine(_ item: DownloadItem, phase: Phase) -> some View {
        HStack(spacing: 5) {
            StatusGlyph(item.download.state.glyph(item.fraction), size: 13)
                .contentTransition(.symbolEffect(.replace))
            Text(statusTitle(phase))
                .fontWeight(.medium)
                .help(item.download.url.absoluteString)
            Spacer(minLength: 8)
            Text(percent(item, phase: phase))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.body)
    }

    private func statusTitle(_ phase: Phase) -> String {
        switch phase {
        case .queued: String(localized: "Waiting")
        case .connecting: String(localized: "Connecting")
        case .transferring: String(localized: "Downloading")
        case .paused: String(localized: "Paused")
        case .verifying: String(localized: "Verifying")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    /// Finished states only; while working, the status line says what's happening.
    @ViewBuilder
    private func badge(_ phase: Phase) -> some View {
        if let (symbol, color) = badgeStyle(phase) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, color)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1.5))
                .symbolEffect(.bounce, value: phase == .completed)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }

    private func badgeStyle(_ phase: Phase) -> (String, Color)? {
        switch phase {
        case .completed: ("checkmark.circle.fill", RocketColor.success)
        case .failed: ("exclamationmark.circle.fill", RocketColor.danger)
        case .cancelled: ("xmark.circle.fill", Color(nsColor: .systemGray))
        default: nil
        }
    }

    // MARK: Progress

    @ViewBuilder
    private func bar(_ item: DownloadItem, phase: Phase) -> some View {
        switch phase {
        case .connecting, .verifying:
            // Real activity with nothing measurable yet.
            ProgressView().progressViewStyle(.linear).controlSize(.small).frame(height: 6)
        default:
            ProgressView(value: barValue(item, phase: phase))
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(barTint(phase))
                .frame(height: 6)
        }
    }

    private func barValue(_ item: DownloadItem, phase: Phase) -> Double {
        switch phase {
        case .completed: 1
        case .queued: 0
        default: min(1, max(0, item.fraction ?? 0))
        }
    }

    private func barTint(_ phase: Phase) -> Color {
        switch phase {
        case .completed: RocketColor.success
        case .failed: RocketColor.danger
        case .paused, .cancelled: Color(nsColor: .systemGray)
        default: RocketColor.accent
        }
    }

    private func percent(_ item: DownloadItem, phase: Phase) -> String {
        if phase == .completed { return 1.0.formatted(.percent.precision(.fractionLength(0))) }
        guard phase != .queued, phase != .connecting else { return "" }
        return item.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? ""
    }

    // MARK: Metrics

    /// Size on the left, live metrics with small symbols on the right; an error takes the whole line.
    @ViewBuilder
    private func infoLine(_ item: DownloadItem, phase: Phase) -> some View {
        if phase == .failed {
            Label {
                Text(item.download.failure?.userMessage ?? String(localized: "The download stopped unexpectedly."))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(RocketColor.warning)
            }
            .font(.callout)
            .imageScale(.small)
        } else {
            HStack(spacing: 12) {
                Text(amount(item, phase: phase))
                Spacer(minLength: 0)
                ForEach(metrics(item, phase: phase), id: \.symbol) { metric in
                    Label(metric.value, systemImage: metric.symbol)
                        .labelStyle(MetricLabelStyle())
                        .help(metric.help)
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private struct Metric {
        let symbol: String
        let value: String
        let help: String
    }

    private func metrics(_ item: DownloadItem, phase: Phase) -> [Metric] {
        switch phase {
        case .transferring:
            var result: [Metric] = []
            if item.speed > 0 {
                result.append(Metric(symbol: "speedometer", value: Format.speed(item.speed), help: String(localized: "Speed")))
            }
            if let seconds = item.secondsLeft {
                let left = Duration.seconds(max(1, Int(seconds.rounded(.up))))
                    .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
                result.append(Metric(symbol: "clock", value: left, help: String(localized: "Time left")))
            }
            return result
        default:
            return []
        }
    }

    /// "1.2 MB of 2.6 MB", or just the received bytes when the size is unknown.
    private func amount(_ item: DownloadItem, phase: Phase) -> String {
        let download = item.download
        switch phase {
        case .queued: return String(localized: "Waiting in queue")
        case .connecting: return String(localized: "Contacting server…")
        case .completed: return Format.bytes(download.totalBytes ?? download.receivedBytes)
        default: break
        }
        let received = Format.bytes(download.receivedBytes)
        guard let total = download.totalBytes else {
            return download.receivedBytes > 0 ? received : String(localized: "Size unknown")
        }
        return String(localized: "\(received) of \(Format.bytes(total))")
    }

    // MARK: Actions

    /// Equal-width buttons like an alert; the default action is on the right.
    @ViewBuilder
    private func buttons(_ item: DownloadItem, phase: Phase) -> some View {
        switch phase {
        case .completed:
            wide("Show in Finder") { model.reveal([id]); close() }
            wide("Open") { model.open(id); close() }.keyboardShortcut(.defaultAction)
        case .failed:
            wide("Close", action: close).keyboardShortcut(.cancelAction)
            wide("Try Again") { Task { await model.resume([id]) } }.keyboardShortcut(.defaultAction)
        case .cancelled:
            wide("Close", action: close).keyboardShortcut(.defaultAction)
        case .paused:
            wide("Cancel") { Task { await model.cancel([id]) } }
            wide("Resume") { Task { await model.resume([id]) } }.keyboardShortcut(.defaultAction)
        default:
            wide("Cancel") { Task { await model.cancel([id]) } }
            wide("Pause") { Task { await model.pause([id]) } }
                .disabled(phase == .verifying)
                .help(phase == .transferring && !item.download.acceptsRanges
                    ? String(localized: "This server can't resume downloads, so pausing starts over from the beginning.") : "")
        }
    }

    private func wide(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
    }
}

/// Small tertiary symbol tight against its value.
private struct MetricLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small).foregroundStyle(.tertiary)
            configuration.title
        }
    }
}
