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
    /// A queue with "Notify me" as its after-action ran dry.
    case queueFinished(DownloadQueue)
}

public enum SidebarFilter: Identifiable, Hashable, Sendable {
    case all, active, completed, failed
    case queue(String)

    public static let statuses: [SidebarFilter] = [.all, .active, .completed, .failed]

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: String(localized: "All downloads")
        case .active: String(localized: "Active")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .queue: String(localized: "Queue")
        }
    }

    public var symbol: String {
        switch self {
        case .all: "tray.full"
        case .active: "arrow.down.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .queue: "list.bullet"
        }
    }

    public func includes(_ download: Download) -> Bool {
        switch self {
        case .all: true
        case .active: download.state.isActive || download.state == .paused
        case .completed: download.state == .completed
        case .failed: download.state == .failed
        case .queue(let id): download.queueID == id && download.state != .cancelled
        }
    }
}

/// State for the download list. Polls the agent at 5 Hz and measures speed from successive snapshots.
@MainActor
@Observable
public final class DownloadsModel {
    public var agent: (any AgentCommanding)?
    public private(set) var items: [DownloadItem] = []
    public internal(set) var queues: [DownloadQueue] = []
    public internal(set) var rules: [DownloadRule] = []
    /// Per-download speed samples for the last 60 s (5 Hz), for the detail view's chart.
    public private(set) var speedSamples: [UUID: [Double]] = [:]
    public var showsInspector = false
    /// Download whose link is being refreshed.
    public var refreshing: Download?
    /// Queue being edited (a new one has an unsaved id).
    public var editingQueue: DownloadQueue?
    private var polls = 0
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
        let matching = items.filter { item in
            filter.includes(item.download)
                && (search.isEmpty || item.download.fileName.localizedCaseInsensitiveContains(search)
                    || item.download.url.absoluteString.localizedCaseInsensitiveContains(search))
        }
        // A queue shows its run order; everything else newest first.
        if case .queue = filter { return matching.sorted { $0.download.position < $1.download.position } }
        return matching
    }

    public func count(_ filter: SidebarFilter) -> Int {
        items.count { filter.includes($0.download) }
    }

    public var totalSpeed: Double { items.reduce(0) { $0 + $1.speed } }
    /// Last 16 aggregate speed samples (one per snapshot), oldest first, for the sparkline.
    public private(set) var speedHistory: [Double] = Array(repeating: 0, count: 16)
    public var transferringCount: Int { items.count { [.probing, .downloading, .verifying].contains($0.download.state) } }
    public var queuedCount: Int { items.count { $0.download.state == .queued } }
    public var isDownloading: Bool { items.contains { $0.download.state == .downloading } }

    /// Bytes of downloads completed in each of the last 24 hours, oldest first; the last bucket is the current hour.
    public func hourlyThroughput(now: Date = .now) -> [Int64] {
        var buckets = Array(repeating: Int64(0), count: 24)
        for item in items {
            guard item.download.state == .completed, let completed = item.download.completedAt else { continue }
            let hoursAgo = Int(now.timeIntervalSince(completed) / 3600)
            if (0..<24).contains(hoursAgo) { buckets[23 - hoursAgo] += item.download.totalBytes ?? item.download.receivedBytes }
        }
        return buckets
    }
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
        // Queues change rarely: reload them every 5 s and after queue commands.
        if polls % 25 == 0 { await refreshQueues() }
        polls += 1
        apply(downloads, now: now)
    }

    public func refreshQueues() async {
        if let agent, case .queues(let queues)? = try? await agent.send(.queues), queues != self.queues { self.queues = queues }
    }

    public func title(for filter: SidebarFilter) -> String {
        if case .queue(let id) = filter { return queues.first { $0.id == id }?.name ?? filter.title }
        return filter.title
    }

    func apply(_ downloads: [Download], now: ContinuousClock.Instant) {
        if let lastStates {
            for download in downloads where lastStates[download.id] != download.state {
                if download.state == .completed { onEvent?(.completed(download)) }
                if download.state == .failed { onEvent?(.failed(download)) }
            }
        }
        if let lastStates {
            // "Notify me" after-action: a queue that had work in flight and now has none.
            let pending: (Download) -> Bool = { $0.state.isActive }
            let before = Set(items.map(\.download).filter { lastStates[$0.id].map { $0.isActive } ?? false }.map(\.queueID))
            let after = Set(downloads.filter(pending).map(\.queueID))
            for queue in queues where queue.postAction == .notify && before.contains(queue.id) && !after.contains(queue.id) {
                onEvent?(.queueFinished(queue))
            }
        }
        lastStates = Dictionary(uniqueKeysWithValues: downloads.map { ($0.id, $0.state) })
        let next = downloads.map { DownloadItem(download: $0, speed: measureSpeed($0, now: now)) }
        let ids = Set(next.map(\.id))
        for item in next where item.download.state == .downloading {
            speedSamples[item.id, default: []].append(item.speed)
            if speedSamples[item.id]!.count > 300 { speedSamples[item.id]!.removeFirst() }
        }
        speedSamples = speedSamples.filter { ids.contains($0.key) }
        samples = samples.filter { ids.contains($0.key) }
        selection.formIntersection(ids)
        if next != items { items = next }
        speedHistory = Array((speedHistory + [totalSpeed]).suffix(16))
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
            connections: settings.connections, queueID: currentQueueID, queues: queues, agent: agent,
            existing: items.map(\.download)
        )
    }

    /// New downloads go to the queue being viewed, else the default queue.
    private var currentQueueID: String {
        if case .queue(let id) = filter { return id }
        return DownloadQueue.defaultID
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

    /// FR-SPD-01: applies live to every running connection.
    public func setGlobalLimit(_ bytesPerSecond: Int64?) async {
        settings.globalSpeedLimit = bytesPerSecond
        await run(.setLimit(downloadID: nil, bytesPerSecond: bytesPerSecond))
    }

    /// FR-SPD-02: per-download limit.
    public func setLimit(_ ids: some Sequence<UUID>, bytesPerSecond: Int64?) async {
        for id in ids { await run(.setLimit(downloadID: id, bytesPerSecond: bytesPerSecond)) }
    }

    // MARK: Queues

    /// Returns an error message, or nil on success.
    public func refreshLink(_ id: UUID, to url: URL) async -> String? {
        guard let agent else { return String(localized: "Rocket's background agent is not running.") }
        let result: String?
        switch try? await agent.send(.refreshURL(id: id, url: url)) {
        case .download?: result = nil
        case .error(let message)?: result = message
        default: result = String(localized: "Could not reach the background agent.")
        }
        await refresh()
        return result
    }

    // MARK: Details

    public func details(_ id: UUID) async -> DownloadDetails? {
        guard let agent, case .details(let details)? = try? await agent.send(.details(id: id)) else { return nil }
        return details
    }

    // MARK: Rules

    public func refreshRules() async {
        if let agent, case .rules(let rules)? = try? await agent.send(.rules) { self.rules = rules }
    }

    public func saveRule(_ rule: DownloadRule) async {
        var rule = rule
        if !rules.contains(where: { $0.id == rule.id }) { rule.priority = (rules.map(\.priority).max() ?? 0) + 1 }
        await run(.saveRule(rule))
        await refreshRules()
    }

    public func deleteRule(_ id: String) async {
        await run(.deleteRule(id: id))
        await refreshRules()
    }

    /// Rules run top to bottom; dragging changes their priority.
    public func moveRules(from source: IndexSet, to destination: Int) async {
        var ordered = rules
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, var rule) in ordered.enumerated() where rule.priority != index {
            rule.priority = index
            await run(.saveRule(rule))
        }
        await refreshRules()
    }

    public func newQueue() {
        editingQueue = DownloadQueue(name: String(localized: "New Queue"), sortOrder: (queues.map(\.sortOrder).max() ?? 0) + 1)
    }

    public func saveQueue(_ queue: DownloadQueue) async {
        await run(.saveQueue(queue))
        await refreshQueues()
        filter = .queue(queue.id)
    }

    public func deleteQueue(_ id: String) async {
        await run(.deleteQueue(id: id))
        await refreshQueues()
        if filter == .queue(id) { filter = .all }
    }

    /// Moves downloads into a queue, before another download or at the end.
    public func move(_ ids: [UUID], toQueue queueID: String, before: UUID? = nil) async {
        await run(.move(ids: ids, toQueue: queueID, before: before))
    }

    /// Reorders within the current queue after a drag in the list.
    public func moveInCurrentQueue(from source: IndexSet, to destination: Int) async {
        guard case .queue(let queueID) = filter else { return }
        let visible = visibleItems
        let moving = source.map { visible[$0].id }
        let before = visible[destination...].first { !moving.contains($0.id) }?.id
        await move(moving, toQueue: queueID, before: before)
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
