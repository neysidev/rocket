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

/// History sort (FR-APP-07). Queue views always show run order.
public enum DownloadSort: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, name, size, progress, status

    public var id: Self { self }
    public var title: String {
        switch self {
        case .newest: String(localized: "Newest")
        case .oldest: String(localized: "Oldest")
        case .name: String(localized: "Name")
        case .size: String(localized: "Size")
        case .progress: String(localized: "Progress")
        case .status: String(localized: "Status")
        }
    }
}

/// Main window layout; persisted across launches.
public enum DownloadViewMode: String, CaseIterable, Identifiable, Sendable {
    case list, grid

    public var id: Self { self }
    public var title: String { self == .list ? String(localized: "List") : String(localized: "Grid") }
    public var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

/// File size refinement shown as a removable chip.
public enum SizeFilter: String, CaseIterable, Identifiable, Sendable {
    case any, small, medium, large, huge

    public var id: Self { self }
    public var title: String {
        switch self {
        case .any: String(localized: "Any Size")
        case .small: String(localized: "Under 10 MB")
        case .medium: String(localized: "10 MB – 100 MB")
        case .large: String(localized: "100 MB – 1 GB")
        case .huge: String(localized: "Over 1 GB")
        }
    }

    func includes(_ bytes: Int64?) -> Bool {
        guard self != .any else { return true }
        guard let bytes else { return false }
        switch self {
        case .any: return true
        case .small: return bytes < 10_000_000
        case .medium: return (10_000_000..<100_000_000).contains(bytes)
        case .large: return (100_000_000..<1_000_000_000).contains(bytes)
        case .huge: return bytes >= 1_000_000_000
        }
    }
}

/// Date-added refinement shown as a removable chip.
public enum DateFilter: String, CaseIterable, Identifiable, Sendable {
    case any, today, week, month

    public var id: Self { self }
    public var title: String {
        switch self {
        case .any: String(localized: "Any Time")
        case .today: String(localized: "Today")
        case .week: String(localized: "Past 7 Days")
        case .month: String(localized: "Past 30 Days")
        }
    }

    func includes(_ date: Date, now: Date = .now) -> Bool {
        switch self {
        case .any: true
        case .today: Calendar.current.isDate(date, inSameDayAs: now)
        case .week: now.timeIntervalSince(date) < 7 * 86400
        case .month: now.timeIntervalSince(date) < 30 * 86400
        }
    }
}

public enum SidebarFilter: Identifiable, Hashable, Sendable {
    case all, active, queued, completed, failed
    case queue(String)

    public static let statuses: [SidebarFilter] = [.all, .active, .queued, .completed, .failed]

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: String(localized: "All Downloads")
        case .active: String(localized: "Active")
        case .queued: String(localized: "Queued")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .queue: String(localized: "Queue")
        }
    }

    public var symbol: String {
        switch self {
        case .all: "tray.and.arrow.down"
        case .active: "play"
        case .queued: "clock"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .queue: "list.bullet"
        }
    }

    public func includes(_ download: Download) -> Bool {
        switch self {
        case .all: true
        // Running or paused; waiting downloads live under Queued.
        case .active: [.probing, .downloading, .verifying, .paused].contains(download.state)
        case .queued: download.state == .queued
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
    /// Download whose details sheet is open.
    public var detailsID: UUID?
    /// The toolbar search field is expanded (⌘F).
    public var isSearching = false
    /// Global command palette (⌘K).
    public var isCommandPaletteOpen = false
    /// Download whose link is being refreshed.
    public var refreshing: Download?
    /// Queue being edited (a new one has an unsaved id).
    public var editingQueue: DownloadQueue?
    private var polls = 0
    public var filter: SidebarFilter = .all
    public var search = ""
    public var sort: DownloadSort = .newest
    /// Refinements on top of the sidebar filter and search.
    public var category: FileCategory?
    /// Filter by download host (smart source grouping).
    public var sourceHost: String?
    public var sizeFilter: SizeFilter = .any
    public var dateFilter: DateFilter = .any
    /// Download insights sheet (statistics and throughput).
    public var showInsights = false
    public var viewMode: DownloadViewMode = DownloadViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    /// Called after each snapshot that changed something (Dock tile).
    public var onUpdate: (@MainActor () -> Void)?
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
    /// State changes after the first snapshot (previous, next).
    public var onStateTransition: (@MainActor (UUID, DownloadState, DownloadState) -> Void)?

    public init(agent: (any AgentCommanding)? = nil, settings: AppSettings = AppSettings()) {
        self.agent = agent
        self.settings = settings
    }

    public var visibleItems: [DownloadItem] {
        let now = Date.now
        let matching = items.filter { item in
            filter.includes(item.download)
                && (category == nil || item.category == category)
                && (sourceHost == nil || DownloadSource.host(for: item.download.url) == sourceHost)
                && sizeFilter.includes(item.download.totalBytes)
                && dateFilter.includes(item.download.createdAt, now: now)
                && (search.isEmpty || item.download.fileName.localizedCaseInsensitiveContains(search)
                    || item.download.url.absoluteString.localizedCaseInsensitiveContains(search))
        }
        // A queue shows its run order; everything else follows the chosen sort.
        if case .queue = filter { return matching.sorted { $0.download.position < $1.download.position } }
        switch sort {
        case .newest: return matching // agent sends newest first
        case .oldest: return matching.reversed()
        case .progress: return matching.sorted { ($0.fraction ?? 0) > ($1.fraction ?? 0) }
        case .name: return matching.sorted { $0.download.fileName.localizedStandardCompare($1.download.fileName) == .orderedAscending }
        case .size: return matching.sorted { ($0.download.totalBytes ?? -1) > ($1.download.totalBytes ?? -1) }
        case .status:
            let order: [DownloadState] = [.downloading, .verifying, .probing, .queued, .paused, .failed, .completed, .cancelled]
            return matching.sorted { (order.firstIndex(of: $0.download.state) ?? 0) < (order.firstIndex(of: $1.download.state) ?? 0) }
        }
    }

    public var hasRefinements: Bool { category != nil || sourceHost != nil || sizeFilter != .any || dateFilter != .any }

    public func clearRefinements() {
        category = nil
        sourceHost = nil
        sizeFilter = .any
        dateFilter = .any
    }

    public var statistics: DownloadStatistics { DownloadStatistics.compute(from: items.map(\.download)) }

    /// Distinct hosts present in history, for source filters.
    public var sourceHosts: [String] {
        Array(Set(items.map { DownloadSource.host(for: $0.download.url) })).sorted()
    }

    /// 1-based place in line for each waiting download, per queue.
    public var queuePositions: [UUID: Int] {
        var next: [String: Int] = [:]
        var result: [UUID: Int] = [:]
        for item in items.filter({ $0.download.state == .queued }).sorted(by: { $0.download.position < $1.download.position }) {
            next[item.download.queueID, default: 0] += 1
            result[item.id] = next[item.download.queueID]
        }
        return result
    }

    /// False until the first snapshot arrives from the agent.
    public var hasLoaded: Bool { lastStates != nil }

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
                if let previous = lastStates[download.id] {
                    onStateTransition?(download.id, previous, download.state)
                }
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
        if next != items {
            items = next
            onUpdate?()
        }
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
    public func beginAdding(_ links: [URL]? = nil, folder: URL? = nil) {
        let links = links ?? LinkExtractor.urls(in: NSPasteboard.general.string(forType: .string) ?? "")
        adding = AddDownloadsModel(
            text: links.map(\.absoluteString).joined(separator: "\n"), folder: folder ?? settings.folder,
            connections: settings.connections, queueID: currentQueueID, queues: queues, agent: agent,
            existing: items.map(\.download), defaultResolution: settings.defaultDuplicateResolution
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

    public func showDetails(_ id: UUID) {
        selection = [id]
        detailsID = id
    }

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

    /// Overall progress of running downloads with a known size, for the Dock.
    public var overallFraction: Double? {
        let running = items.map(\.download).filter { $0.state.isActive && $0.totalBytes != nil }
        let total = running.reduce(Int64(0)) { $0 + ($1.totalBytes ?? 0) }
        guard total > 0 else { return nil }
        return Double(running.reduce(Int64(0)) { $0 + $1.receivedBytes }) / Double(total)
    }

    /// Removes completed and cancelled downloads from the list; files stay on disk (FR-APP-07).
    public func clearCompleted() async {
        await remove(items.filter { [.completed, .cancelled].contains($0.download.state) }.map(\.id))
    }

    public var hasFinished: Bool { items.contains { [.completed, .cancelled].contains($0.download.state) } }

    public func pauseAll() async { await pause(items.map(\.id)) }
    public func pauseQueue(_ id: String) async { await pause(items.filter { $0.download.queueID == id }.map(\.id)) }
    public func resumeQueue(_ id: String) async {
        await resume(items.filter { $0.download.queueID == id && $0.download.state == .paused }.map(\.id))
    }
    public func queueIsRunning(_ id: String) -> Bool { items.contains { $0.download.queueID == id && $0.download.state.isActive } }
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
