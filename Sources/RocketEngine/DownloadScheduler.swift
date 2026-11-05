import Foundation
import RocketCore

/// Owns every download's lifecycle in the agent: runs each queue up to its own limit inside its schedule,
/// pauses, resumes and cancels, recovers after a crash, retries when the network returns, and runs a queue's
/// after-action when it runs dry. One per agent.
public actor DownloadScheduler {
    private let repository: any DownloadRepository
    private let checkpoints: any CheckpointStore
    private let queueStore: any QueueRepository
    private let ruleStore: (any RuleRepository)?
    private let now: @Sendable () -> Date
    /// Runs a queue's after-action (sleep, shut down, …) once it has nothing left to do.
    private let runPostAction: @Sendable (DownloadQueue) async -> Void
    /// Called with true when downloads start running and false when none are left (sleep prevention).
    private let onActivityChange: @Sendable (Bool) async -> Void
    private let transport: any HTTPTransport
    private let maxActive: Int
    private let retry: RetryPolicy
    private let checkpointInterval: Duration
    private let log = Rocket.logger("Engine")

    /// Running downloads. The scheduler owns these tasks and cancels them on pause, cancel and shutdown.
    private var running: [UUID: Task<Void, Never>] = [:]
    private var coordinators: [UUID: DownloadCoordinator] = [:]
    private let globalLimiter: BandwidthLimiter
    private var downloadLimiters: [UUID: BandwidthLimiter] = [:]
    private var queueLimiters: [String: BandwidthLimiter] = [:]
    /// Queue of each running download.
    private var runningQueue: [UUID: String] = [:]
    /// Queues that started work since they were last empty; their after-action fires when they run dry.
    private var busyQueues: Set<String> = []
    private var wasActive = false
    /// Last 200 log entries per download. ponytail: in memory, lost when the agent restarts; persist with the
    /// download if users need history across restarts.
    private var logs: [UUID: [LogEntry]] = [:]
    private let defaults: RocketDefaults
    /// Why a running task is being stopped, so its cancellation lands in the right state.
    private var stopping: [UUID: DownloadState] = [:]

    public init(
        repository: any DownloadRepository, checkpoints: any CheckpointStore, queues: any QueueRepository,
        rules: (any RuleRepository)? = nil,
        transport: any HTTPTransport, maxActive: Int = 32, retry: RetryPolicy = RetryPolicy(),
        checkpointInterval: Duration = .seconds(2), defaults: RocketDefaults = RocketDefaults(),
        now: @escaping @Sendable () -> Date = { .now },
        runPostAction: @escaping @Sendable (DownloadQueue) async -> Void = { _ in },
        onActivityChange: @escaping @Sendable (Bool) async -> Void = { _ in }
    ) {
        queueStore = queues
        ruleStore = rules
        self.now = now
        self.runPostAction = runPostAction
        self.onActivityChange = onActivityChange
        self.defaults = defaults
        globalLimiter = BandwidthLimiter(bytesPerSecond: defaults.globalSpeedLimit)
        self.repository = repository
        self.checkpoints = checkpoints
        self.transport = transport
        self.maxActive = maxActive
        self.retry = retry
        self.checkpointInterval = checkpointInterval
    }

    /// Crash recovery: anything that was in flight when the agent died goes back to the queue.
    public func start() async throws {
        for var download in try await repository.all() where [.probing, .downloading, .verifying].contains(download.state) {
            download.state = .queued
            try await repository.save(download)
        }
        try await fill()
    }

    // MARK: Commands

    /// What the server says about a URL, for the add sheet.
    public func probe(_ url: URL) async throws -> RemoteFileInfo {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { throw DownloadError.invalidURL }
        return try await transport.probe(url)
    }

    /// Probes the URL (FR-ADD-02), stores the download and queues it. Each option resolves as: what the request
    /// says, else the first matching rule (FR-ORG-02), else the defaults; a download landing in the default folder
    /// goes into its type's subfolder when auto-sort is on (FR-ORG-01).
    public func add(
        url: URL, folder: URL? = nil, fileName: String? = nil, connections: Int? = nil, speedLimit: Int64? = nil,
        queueID: String? = nil
    ) async throws -> Download {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { throw DownloadError.invalidURL }
        let info = try await transport.probe(url)
        let name = FileNameSanitizer.sanitize(fileName ?? info.suggestedFileName ?? url.lastPathComponent)
        let rule = DownloadRule.first(in: try await ruleStore?.rules() ?? [], url: url, fileName: name, size: info.totalBytes)

        var destination = folder ?? rule?.action.folderPath.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? defaults.folder
        if folder == nil, rule?.action.folderPath == nil, defaults.autoSort {
            destination = destination.appending(path: FileCategory(fileName: name).folderName, directoryHint: .isDirectory)
        }
        let knownQueues = Set(try await queues().map(\.id))
        let queue = [queueID, rule?.action.queueID].compactMap { $0 }.first(where: knownQueues.contains) ?? DownloadQueue.defaultID

        var download = Download(
            url: url, destinationPath: destination.path, fileName: name,
            connections: min(16, max(1, connections ?? rule?.action.connections ?? defaults.connections))
        )
        download.remoteInfo = info
        download.speedLimit = speedLimit ?? rule?.action.speedLimit
        download.queueID = queue
        try await repository.save(download)
        log(download.id, "Added: \(info.totalBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "size unknown"), \(info.acceptsRanges ? "resumable" : "no range support")")
        if let rule { log(download.id, "Rule “\(rule.name)” applied") }
        log.info("Queued \(download.id, privacy: .public)")
        try await fill()
        return try await repository.download(id: download.id) ?? download
    }

    public func pause(id: UUID) async throws {
        var download = try await existing(id)
        if let task = running[id] {
            stopping[id] = .paused
            task.cancel()
            await task.value
        } else if download.state.canTransition(to: .paused) || download.state == .queued {
            download.state = .paused
            try await repository.save(download)
        }
    }

    public func resume(id: UUID) async throws {
        var download = try await existing(id)
        guard download.state == .paused || download.state == .failed else { return }
        download.state = .queued
        download.failure = nil
        try await repository.save(download)
        try await fill()
    }

    /// Stops the download and deletes its partial file.
    public func cancel(id: UUID) async throws {
        if let task = running[id] {
            stopping[id] = .cancelled
            task.cancel()
            await task.value
        }
        var download = try await existing(id)
        guard download.state != .completed else { return }
        try? FileManager.default.removeItem(at: download.partFileURL)
        try await checkpoints.saveCheckpoint(downloadID: id, segments: [])
        download.state = .cancelled
        try await repository.save(download)
    }

    /// Removes the download from the list. Unfinished work is cancelled; a completed file is moved to the
    /// Trash only when `deleteFile` is set (FR-APP-07).
    public func remove(id: UUID, deleteFile: Bool) async throws {
        if let task = running[id] {
            stopping[id] = .cancelled
            task.cancel()
            await task.value
        }
        let download = try await existing(id)
        try? FileManager.default.removeItem(at: download.partFileURL)
        if deleteFile, download.state == .completed {
            try? FileManager.default.trashItem(at: download.fileURL, resultingItemURL: nil)
        }
        try await checkpoints.saveCheckpoint(downloadID: id, segments: [])
        try await repository.delete(id: id)
    }

    /// Changes a limit live. `id` nil = global limit, which is also remembered across restarts.
    public func setLimit(id: UUID?, bytesPerSecond: Int64?) async throws {
        guard let id else {
            defaults.globalSpeedLimit = bytesPerSecond
            return await globalLimiter.setRate(bytesPerSecond)
        }
        var download = try await existing(id)
        download.speedLimit = bytesPerSecond
        try await repository.save(download)
        await downloadLimiters[id]?.setRate(bytesPerSecond)
    }

    public var globalLimit: Int64? {
        get async { await globalLimiter.bytesPerSecond }
    }

    // MARK: Details

    public func details(id: UUID) async throws -> DownloadDetails {
        if let coordinator = coordinators[id] {
            return DownloadDetails(
                segments: await coordinator.segments, activeConnections: await coordinator.activeConnections,
                connectionLimit: await coordinator.connectionLimit, log: logs[id] ?? []
            )
        }
        return DownloadDetails(segments: try await checkpoints.segments(downloadID: id), activeConnections: 0, connectionLimit: nil, log: logs[id] ?? [])
    }

    private func log(_ id: UUID, _ message: String, isError: Bool = false) {
        logs[id, default: []].append(LogEntry(message: message, isError: isError))
        if logs[id]!.count > 200 { logs[id]!.removeFirst(logs[id]!.count - 200) }
    }

    private func appendLog(_ id: UUID, _ entry: LogEntry) {
        log(id, entry.message, isError: entry.isError)
    }

    // MARK: Rules

    public func rules() async throws -> [DownloadRule] {
        try await ruleStore?.rules() ?? []
    }

    public func saveRule(_ rule: DownloadRule) async throws {
        try await ruleStore?.save(rule)
    }

    public func deleteRule(id: String) async throws {
        try await ruleStore?.deleteRule(id: id)
    }

    // MARK: Queues

    /// All queues in display order; creates the default queue if missing.
    public func queues() async throws -> [DownloadQueue] {
        var queues = try await queueStore.queues()
        if !queues.contains(where: \.isDefault) {
            let fallback = DownloadQueue(id: DownloadQueue.defaultID, name: String(localized: "Default"), sortOrder: -1)
            try await queueStore.save(fallback)
            queues.insert(fallback, at: 0)
        }
        return queues
    }

    public func saveQueue(_ queue: DownloadQueue) async throws {
        var queue = queue
        queue.maxActive = min(16, max(1, queue.maxActive))
        try await queueStore.save(queue)
        await queueLimiters[queue.id]?.setRate(queue.speedLimit)
        try await fill()
    }

    public func deleteQueue(id: String) async throws {
        try await queueStore.deleteQueue(id: id)
        queueLimiters[id] = nil
        try await fill()
    }

    /// Moves downloads to `queueID`, placed before `before` (or at the end), keeping their order (FR-QUE-03).
    public func move(ids: [UUID], toQueue queueID: String, before: UUID?) async throws {
        let siblings = try await repository.all()
            .filter { $0.queueID == queueID && !ids.contains($0.id) }
            .sorted { $0.position < $1.position }
        let index = before.flatMap { id in siblings.firstIndex { $0.id == id } } ?? siblings.endIndex
        let lower = index > 0 ? siblings[index - 1].position : (siblings.first?.position ?? 0) - Double(ids.count + 1)
        let upper = index < siblings.endIndex ? siblings[index].position : lower + Double(ids.count + 1)
        let step = (upper - lower) / Double(ids.count + 1)
        for (offset, id) in ids.enumerated() {
            var download = try await existing(id)
            download.queueID = queueID
            download.position = lower + step * Double(offset + 1)
            try await repository.save(download)
        }
        try await fill()
    }

    /// Re-evaluates schedules: opens queues whose window started, parks downloads of queues whose window ended.
    public func tick() async throws {
        try await fill()
    }

    /// Downloads with live progress for running ones.
    public func snapshot() async throws -> [Download] {
        var downloads = try await repository.all()
        for index in downloads.indices {
            if let coordinator = coordinators[downloads[index].id] {
                downloads[index].receivedBytes = await coordinator.receivedBytes
            }
        }
        return downloads
    }

    /// Network is back (or the Mac woke up): retry downloads that failed for transient reasons.
    public func networkAvailable() async throws {
        for var download in try await repository.all() where download.state == .failed && download.failure?.kind == .transient {
            download.state = .queued
            try await repository.save(download)
        }
        try await fill()
    }

    // MARK: Running

    private func existing(_ id: UUID) async throws -> Download {
        guard let download = try await repository.download(id: id) else { throw SchedulerError.notFound(id) }
        return download
    }

    /// For each queue inside its schedule: start queued downloads in order while it has room. Queues outside
    /// their schedule have running downloads sent back to the queue.
    private func fill() async throws {
        let queues = try await queues()
        let downloads = try await repository.all()
        let date = now()
        for queue in queues {
            let members = downloads.filter { $0.queueID == queue.id }
            if let schedule = queue.schedule, !schedule.isOpen(at: date) {
                for id in runningQueue.filter({ $0.value == queue.id }).keys { await stop(id, as: .queued) }
                continue
            }
            let queued = members.filter { $0.state == .queued && running[$0.id] == nil }.sorted { $0.position < $1.position }
            for download in queued {
                let active = runningQueue.values.count { $0 == queue.id }
                guard active < queue.maxActive, running.count < maxActive else { break }
                start(download.id, in: queue)
            }
        }
        try await finishIdleQueues(queues)
        await reportActivity()
    }

    private func start(_ id: UUID, in queue: DownloadQueue) {
        runningQueue[id] = queue.id
        busyQueues.insert(queue.id)
        if queueLimiters[queue.id] == nil { queueLimiters[queue.id] = BandwidthLimiter(bytesPerSecond: queue.speedLimit) }
        running[id] = Task { await self.perform(id) }
    }

    private func stop(_ id: UUID, as state: DownloadState) async {
        guard let task = running[id] else { return }
        stopping[id] = state
        task.cancel()
        await task.value
    }

    /// FR-QUE-05: a queue that did work and now has nothing queued or running fires its after-action once.
    private func finishIdleQueues(_ queues: [DownloadQueue]) async throws {
        guard !busyQueues.isEmpty else { return }
        let downloads = try await repository.all()
        for queue in queues where busyQueues.contains(queue.id) {
            let pending = downloads.contains { $0.queueID == queue.id && ($0.state == .queued || $0.state.isRunning) }
            guard !pending, !runningQueue.values.contains(queue.id) else { continue }
            busyQueues.remove(queue.id)
            if queue.postAction != .none {
                log.info("Queue \(queue.name, privacy: .public) finished; running \(queue.postAction.rawValue, privacy: .public)")
                await runPostAction(queue)
            }
        }
    }

    private func reportActivity() async {
        let active = !running.isEmpty
        guard active != wasActive else { return }
        wasActive = active
        await onActivityChange(active)
    }

    private func perform(_ id: UUID) async {
        do {
            try await download(id)
        } catch {
            await handle(error, for: id)
        }
        running[id] = nil
        runningQueue[id] = nil
        coordinators[id] = nil
        downloadLimiters[id] = nil
        stopping[id] = nil
        do { try await fill() } catch { log.error("Queue refill failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func download(_ id: UUID) async throws {
        var download = try await existing(id)
        try await set(&download, .probing)
        let folder = URL(filePath: download.destinationPath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let file = try PartFile(url: download.partFileURL, size: download.totalBytes)
        file.tag(downloadID: id)
        let checkpoints = checkpoints
        let limiter = BandwidthLimiter(bytesPerSecond: download.speedLimit)
        downloadLimiters[id] = limiter
        let limiters = [globalLimiter, queueLimiters[download.queueID], limiter].compactMap { $0 }
        let logEntry: @Sendable (LogEntry) -> Void = { entry in Task { await self.appendLog(id, entry) } }
        let coordinator = DownloadCoordinator(
            url: download.finalURL ?? download.url, info: download.remoteInfo, file: file,
            segments: try await checkpoints.segments(downloadID: id), connections: download.connections,
            transport: transport, retry: retry, limiters: limiters, onLog: logEntry, checkpointInterval: checkpointInterval,
            onCheckpoint: { try await checkpoints.saveCheckpoint(downloadID: id, segments: $0) }
        )
        coordinators[id] = coordinator
        log(id, coordinator.isSegmented
            ? "Downloading with up to \(download.connections) connections"
            : "Downloading over a single connection (server does not support ranges)")
        try await set(&download, .downloading)
        try await coordinator.run()

        try await set(&download, .verifying)
        let knownTotal = await coordinator.totalBytes
        let total = try knownTotal ?? file.size()
        let final = try DownloadFinalizer.finalize(file, expectedBytes: total, folder: folder, fileName: download.fileName, source: download.url)
        try await checkpoints.saveCheckpoint(downloadID: id, segments: [])
        download.fileName = final.lastPathComponent
        download.totalBytes = total
        download.receivedBytes = total
        download.completedAt = .now
        try await set(&download, .completed)
        log(id, "Completed: saved as \(final.lastPathComponent)")
        log.info("Completed \(id, privacy: .public)")
    }

    private func handle(_ error: any Error, for id: UUID) async {
        do {
            guard var download = try await repository.download(id: id) else { return }
            download.receivedBytes = try await checkpoints.segments(downloadID: id).reduce(0) { $0 + $1.received }
            if let reason = stopping[id] {
                // Pause keeps the part file; cancel() cleans up after us.
                download.state = reason
                log(id, reason == .queued ? "Queue window closed; waiting for the next one" : "\(reason.rawValue.capitalized)")
            } else if error is CancellationError {
                download.state = .queued // agent shutting down: pick it up on next start
            } else if case DownloadError.remoteFileChanged = error, download.failure != .remoteFileChanged {
                // FR-ENG-06: the server copy changed. Restart from scratch once, and say why.
                try? FileManager.default.removeItem(at: download.partFileURL)
                try await checkpoints.saveCheckpoint(downloadID: id, segments: [])
                download.remoteInfo = try await transport.probe(download.url)
                download.receivedBytes = 0
                download.failure = .remoteFileChanged
                download.state = .queued
                log(id, "File changed on the server; restarting from the beginning", isError: true)
                log.info("Restarting \(id, privacy: .public): file changed on server")
            } else {
                download.failure = error as? DownloadError ?? .network(code: (error as? URLError)?.code.rawValue ?? -1)
                download.state = .failed
                log(id, "Failed: \(download.failure?.userMessage ?? String(describing: error))", isError: true)
                log.error("Failed \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            try await repository.save(download)
        } catch {
            log.error("Could not record failure for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func set(_ download: inout Download, _ state: DownloadState) async throws {
        download.state = state
        try await repository.save(download)
    }
}

extension DownloadState {
    /// The agent is working on it right now.
    var isRunning: Bool { [.probing, .downloading, .verifying].contains(self) }
}

public enum SchedulerError: Error, Sendable, Equatable {
    case notFound(UUID)
}
