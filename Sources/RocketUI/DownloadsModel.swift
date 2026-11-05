import AppKit
import Foundation
import Observation
import RocketCore
import RocketIPC

/// One row's worth of data: the agent's download plus speed measured on this side.
public struct DownloadItem: Identifiable, Equatable, Sendable {
    public var download: Download
    /// Bytes per second, smoothed.
    public var speed: Double

    public init(download: Download, speed: Double = 0) {
        self.download = download
        self.speed = speed
    }

    public var id: UUID { download.id }
    public var category: FileCategory { FileCategory(fileName: download.fileName) }

    public var fraction: Double? {
        guard let total = download.totalBytes, total > 0 else { return download.state == .completed ? 1 : nil }
        return Double(download.receivedBytes) / Double(total)
    }

    public var secondsLeft: Double? {
        guard speed > 0, let total = download.totalBytes else { return nil }
        return Double(total - download.receivedBytes) / speed
    }

    /// "ubuntu.iso, downloading, 62 percent, 84 megabytes per second, 2 minutes left"
    public var accessibilityLabel: String {
        var parts = [download.fileName, download.state.title]
        if download.state == .downloading || download.state == .paused, let fraction {
            parts.append(fraction.formatted(.percent.precision(.fractionLength(0))))
        }
        if download.state == .downloading, speed > 0 { parts.append(Format.speed(speed)) }
        if download.state == .downloading, let left = secondsLeft { parts.append(Format.timeLeft(left)) }
        if download.state == .failed, let failure = download.failure { parts.append(failure.userMessage) }
        return parts.joined(separator: ", ")
    }
}

public enum DownloadEvent: Equatable, Sendable {
    case completed(Download)
    case failed(Download)
}

public enum SidebarFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, active, completed, failed

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: String(localized: "All downloads")
        case .active: String(localized: "Active")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        }
    }

    public var symbol: String {
        switch self {
        case .all: "tray.full"
        case .active: "arrow.down.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    public func includes(_ download: Download) -> Bool {
        switch self {
        case .all: true
        case .active: download.state.isActive || download.state == .paused
        case .completed: download.state == .completed
        case .failed: download.state == .failed
        }
    }
}

/// State for the download list. Polls the agent at 5 Hz and measures speed from successive snapshots.
@MainActor
@Observable
public final class DownloadsModel {
    public var agent: (any AgentCommanding)?
    public private(set) var items: [DownloadItem] = []
    public var filter: SidebarFilter = .all
    public var search = ""
    public var selection: Set<UUID> = []
    /// Last command error, shown to the user once.
    public var alert: String?
    /// The add sheet, when open.
    public var adding: AddDownloadsModel?
    public let settings: AppSettings

    private var samples: [UUID: (bytes: Int64, time: ContinuousClock.Instant, speed: Double)] = [:]
    /// Last seen state per download; nil until the first snapshot, so existing history does not notify.
    private var lastStates: [UUID: DownloadState]?
    /// Called when a download finishes or fails while the app is watching.
    public var onEvent: (@MainActor (DownloadEvent) -> Void)?

    public init(agent: (any AgentCommanding)? = nil, settings: AppSettings = AppSettings()) {
        self.agent = agent
        self.settings = settings
    }

    public var visibleItems: [DownloadItem] {
        items.filter { item in
            filter.includes(item.download)
                && (search.isEmpty || item.download.fileName.localizedCaseInsensitiveContains(search)
                    || item.download.url.absoluteString.localizedCaseInsensitiveContains(search))
        }
    }

    public func count(_ filter: SidebarFilter) -> Int {
        items.count { filter.includes($0.download) }
    }

    public var totalSpeed: Double { items.reduce(0) { $0 + $1.speed } }
    public var hasRunning: Bool { items.contains { $0.download.state.isActive } }
    public var hasPaused: Bool { items.contains { $0.download.state == .paused } }

    // MARK: Polling

    /// ponytail: polls at 5 Hz; switch to the agent pushing coalesced snapshots (TRD IPC events) when it exists.
    public func poll(every interval: Duration = .milliseconds(200)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }

    public func refresh(now: ContinuousClock.Instant = .now) async {
        guard let agent, case .snapshot(let downloads)? = try? await agent.send(.snapshot) else { return }
        apply(downloads, now: now)
    }

    func apply(_ downloads: [Download], now: ContinuousClock.Instant) {
        if let lastStates {
            for download in downloads where lastStates[download.id] != download.state {
                if download.state == .completed { onEvent?(.completed(download)) }
                if download.state == .failed { onEvent?(.failed(download)) }
            }
        }
        lastStates = Dictionary(uniqueKeysWithValues: downloads.map { ($0.id, $0.state) })
        let next = downloads.map { DownloadItem(download: $0, speed: measureSpeed($0, now: now)) }
        let ids = Set(next.map(\.id))
        samples = samples.filter { ids.contains($0.key) }
        selection.formIntersection(ids)
        if next != items { items = next }
    }

    private func measureSpeed(_ download: Download, now: ContinuousClock.Instant) -> Double {
        guard download.state == .downloading else {
            samples[download.id] = nil
            return 0
        }
        guard let last = samples[download.id] else {
            samples[download.id] = (download.receivedBytes, now, 0)
            return 0
        }
        let elapsed = Double((now - last.time).components.attoseconds) / 1e18 + Double((now - last.time).components.seconds)
        guard elapsed >= 0.1 else { return last.speed }
        let instant = max(0, Double(download.receivedBytes - last.bytes) / elapsed)
        let speed = last.speed == 0 ? instant : last.speed * 0.7 + instant * 0.3
        samples[download.id] = (download.receivedBytes, now, speed)
        return speed
    }

    // MARK: Adding

    /// Opens the add sheet with `links`, or with whatever links are on the clipboard.
    public func beginAdding(_ links: [URL]? = nil) {
        let links = links ?? LinkExtractor.urls(in: NSPasteboard.general.string(forType: .string) ?? "")
        adding = AddDownloadsModel(
            text: links.map(\.absoluteString).joined(separator: "\n"), folder: settings.folder,
            connections: settings.connections, agent: agent, existing: items.map(\.download)
        )
    }

    /// After the sheet: show the new (or existing) downloads.
    public func finishAdding(_ ids: [UUID]) async {
        await refresh()
        filter = .all
        search = ""
        selection = Set(ids)
    }

    // MARK: Commands

    public func download(_ id: UUID) -> Download? { items.first { $0.id == id }?.download }

    public func pause(_ ids: some Sequence<UUID>) async {
        for id in ids where download(id)?.state.isActive == true { await run(.pause(id: id)) }
    }

    public func resume(_ ids: some Sequence<UUID>) async {
        for id in ids where [.paused, .failed].contains(download(id)?.state) { await run(.resume(id: id)) }
    }

    /// Space bar: pause what runs, resume what doesn't.
    public func toggle(_ ids: Set<UUID>) async {
        if ids.contains(where: { download($0)?.state.isActive == true }) {
            await pause(ids)
        } else {
            await resume(ids)
        }
    }

    public func cancel(_ ids: some Sequence<UUID>) async {
        for id in ids { await run(.cancel(id: id)) }
    }

    public func remove(_ ids: some Sequence<UUID>, deleteFiles: Bool = false) async {
        for id in ids { await run(.remove(id: id, deleteFile: deleteFiles)) }
    }

    public func pauseAll() async { await pause(items.map(\.id)) }
    public func resumeAll() async { await resume(items.filter { $0.download.state == .paused }.map(\.id)) }

    public func reveal(_ ids: some Sequence<UUID>) {
        let urls = ids.compactMap(download).map { $0.state == .completed ? $0.fileURL : $0.partFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    public func open(_ id: UUID) {
        guard let download = download(id), download.state == .completed else { return }
        NSWorkspace.shared.open(download.fileURL)
    }

    private func run(_ command: Command) async {
        guard let agent else { return alert = String(localized: "Rocket's background agent is not running.") }
        do {
            if case .error(let message) = try await agent.send(command) { alert = message }
        } catch {
            alert = error.localizedDescription
        }
        await refresh()
    }
}
