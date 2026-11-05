import Foundation
import RocketCore

/// Owns every download's lifecycle in the agent: starts queued downloads up to `maxActive`, pauses,
/// resumes and cancels them, recovers after a crash and retries when the network returns. One per agent.
public actor DownloadScheduler {
    private let repository: any DownloadRepository
    private let checkpoints: any CheckpointStore
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
    private let defaults: RocketDefaults
    /// Why a running task is being stopped, so its cancellation lands in the right state.
    private var stopping: [UUID: DownloadState] = [:]

    public init(
        repository: any DownloadRepository, checkpoints: any CheckpointStore, transport: any HTTPTransport,
        maxActive: Int = 3, retry: RetryPolicy = RetryPolicy(), checkpointInterval: Duration = .seconds(2),
        defaults: RocketDefaults = RocketDefaults()
    ) {
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

    /// Probes the URL (FR-ADD-02), stores the download and queues it.
    public func add(url: URL, folder: URL, fileName: String? = nil, connections: Int = 8, speedLimit: Int64? = nil) async throws -> Download {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { throw DownloadError.invalidURL }
        let info = try await transport.probe(url)
        let name = FileNameSanitizer.sanitize(fileName ?? info.suggestedFileName ?? url.lastPathComponent)
        var download = Download(url: url, destinationPath: folder.path, fileName: name, connections: min(16, max(1, connections)))
        download.remoteInfo = info
        download.speedLimit = speedLimit
        try await repository.save(download)
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

    /// Starts queued downloads, oldest first, while there is room.
    private func fill() async throws {
        let queued = try await repository.all().filter { $0.state == .queued }.sorted { $0.createdAt < $1.createdAt }
        for download in queued where running.count < maxActive && running[download.id] == nil {
            let id = download.id
            running[id] = Task { await self.perform(id) }
        }
    }

    private func perform(_ id: UUID) async {
        do {
            try await download(id)
        } catch {
            await handle(error, for: id)
        }
        running[id] = nil
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
        let coordinator = DownloadCoordinator(
            url: download.finalURL ?? download.url, info: download.remoteInfo, file: file,
            segments: try await checkpoints.segments(downloadID: id), connections: download.connections,
            transport: transport, retry: retry, limiters: [globalLimiter, limiter], checkpointInterval: checkpointInterval,
            onCheckpoint: { try await checkpoints.saveCheckpoint(downloadID: id, segments: $0) }
        )
        coordinators[id] = coordinator
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
        log.info("Completed \(id, privacy: .public)")
    }

    private func handle(_ error: any Error, for id: UUID) async {
        do {
            guard var download = try await repository.download(id: id) else { return }
            download.receivedBytes = try await checkpoints.segments(downloadID: id).reduce(0) { $0 + $1.received }
            if let reason = stopping[id] {
                // Pause keeps the part file; cancel() cleans up after us.
                download.state = reason
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
                log.info("Restarting \(id, privacy: .public): file changed on server")
            } else {
                download.failure = error as? DownloadError ?? .network(code: (error as? URLError)?.code.rawValue ?? -1)
                download.state = .failed
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

public enum SchedulerError: Error, Sendable, Equatable {
    case notFound(UUID)
}
