import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

/// In-memory fake for every persistence port.
actor MemoryRepository: DownloadRepository, CheckpointStore, QueueRepository, RuleRepository {
    var ruleStore: [String: DownloadRule] = [:]
    func rules() -> [DownloadRule] { Array(ruleStore.values) }
    func save(_ rule: DownloadRule) { ruleStore[rule.id] = rule }
    func deleteRule(id: String) { ruleStore[id] = nil }

    var downloads: [UUID: Download] = [:]
    var segments: [UUID: [Segment]] = [:]
    var queueStore: [String: DownloadQueue] = [:]

    func queues() -> [DownloadQueue] { queueStore.values.sorted { $0.sortOrder < $1.sortOrder } }
    func save(_ queue: DownloadQueue) { queueStore[queue.id] = queue }
    func deleteQueue(id: String) {
        queueStore[id] = nil
        for (key, var download) in downloads where download.queueID == id {
            download.queueID = DownloadQueue.defaultID
            downloads[key] = download
        }
    }

    func all() -> [Download] { downloads.values.sorted { $0.createdAt > $1.createdAt } }
    func download(id: UUID) -> Download? { downloads[id] }
    func save(_ download: Download) { downloads[download.id] = download }
    func delete(id: UUID) { downloads[id] = nil }
    func saveCheckpoint(downloadID: UUID, segments: [Segment]) { self.segments[downloadID] = segments }
    func segments(downloadID: UUID) -> [Segment] { segments[downloadID] ?? [] }
}

@Suite struct DownloadSchedulerTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "SchedulerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let repository = MemoryRepository()
    let scheduler: DownloadScheduler
    let size = 6 * Int(SegmentPlanner.mebibyte)

    init() {
        scheduler = DownloadScheduler(
            repository: repository, checkpoints: repository, queues: repository, transport: URLSessionHTTPTransport(),
            retry: RetryPolicy(baseDelay: .milliseconds(5), maxDelay: .milliseconds(20)),
            checkpointInterval: .milliseconds(50),
            defaults: RocketDefaults(store: UserDefaults(suiteName: "SchedulerTests-\(UUID().uuidString)")!)
        )
    }

    /// Polls until the download reaches one of `states`.
    @discardableResult
    func wait(for id: UUID, _ states: Set<DownloadState>, timeout: Duration = .seconds(20)) async throws -> Download {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let download = try await scheduler.snapshot().first(where: { $0.id == id }), states.contains(download.state) {
                return download
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for \(states)")
        throw CancellationError()
    }

    func finalBytes(_ download: Download) throws -> Data {
        try Data(contentsOf: folder.appending(path: download.fileName))
    }

    @Test func downloadsToFolder() async throws {
        let server = try await RocketTestServer()
        let added = try await scheduler.add(url: server.url("/file/\(size)?name=disk.img"), folder: folder)
        #expect(added.fileName == "disk.img")
        #expect(added.totalBytes == Int64(size))

        let done = try await wait(for: added.id, [.completed, .failed])
        #expect(done.state == .completed)
        #expect(done.receivedBytes == Int64(size))
        #expect(try finalBytes(done) == RocketTestServer.content(count: size))
        #expect(await repository.segments(downloadID: added.id).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: added.partFileURL.path))
    }

    @Test func pauseAndResume() async throws {
        let server = try await RocketTestServer()
        let added = try await scheduler.add(url: server.url("/file/\(size)?delayMs=50&name=slow.bin"), folder: folder)
        try await Task.sleep(for: .milliseconds(300))
        try await scheduler.pause(id: added.id)

        let paused = try await wait(for: added.id, [.paused, .completed])
        #expect(paused.receivedBytes > 0 && paused.receivedBytes < Int64(size))
        #expect(FileManager.default.fileExists(atPath: added.partFileURL.path))

        try await scheduler.resume(id: added.id)
        let done = try await wait(for: added.id, [.completed, .failed])
        #expect(done.state == .completed)
        #expect(try finalBytes(done) == RocketTestServer.content(count: size))
    }

    @Test func cancelDeletesPartialFile() async throws {
        let server = try await RocketTestServer()
        let added = try await scheduler.add(url: server.url("/file/\(size)?delayMs=50&name=gone.bin"), folder: folder)
        try await Task.sleep(for: .milliseconds(200))
        try await scheduler.cancel(id: added.id)
        #expect(try await wait(for: added.id, [.cancelled, .completed]).state == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: added.partFileURL.path))
    }

    @Test func recoversDownloadsInterruptedByCrash() async throws {
        let server = try await RocketTestServer()
        let url = server.url("/file/\(size)")
        var download = Download(url: url, destinationPath: folder.path, fileName: "crashed.bin", state: .downloading)
        download.remoteInfo = try await URLSessionHTTPTransport().probe(url)
        await repository.save(download)

        try await scheduler.start()
        let done = try await wait(for: download.id, [.completed, .failed])
        #expect(done.state == .completed)
        #expect(try finalBytes(done) == RocketTestServer.content(count: size))
    }

    @Test func restartsWhenServerFileChanges() async throws {
        let server = try await RocketTestServer()
        let added = try await scheduler.add(url: server.url("/file/\(size)?delayMs=50"), folder: folder)
        try await Task.sleep(for: .milliseconds(300))
        try await scheduler.pause(id: added.id)
        try await wait(for: added.id, [.paused, .completed])

        server.setVersion("2")
        try await scheduler.resume(id: added.id)
        let done = try await wait(for: added.id, [.completed, .failed])
        #expect(done.state == .completed)
        #expect(done.failure == .remoteFileChanged) // the reason the user is shown
        #expect(try finalBytes(done) == RocketTestServer.content(count: size, version: "2"))
    }

    @Test func retriesTransientFailuresWhenNetworkReturns() async throws {
        let server = try await RocketTestServer()
        // One connection and five 503s: exactly enough to exhaust the retry policy.
        let failing = server.url("/file/\(size)?fail=503&failCount=5")
        var download = Download(url: failing, destinationPath: folder.path, fileName: "flaky.bin", connections: 1)
        download.remoteInfo = try await URLSessionHTTPTransport().probe(server.url("/file/\(size)"))
        download.finalURL = failing
        await repository.save(download)

        try await scheduler.start()
        let failed = try await wait(for: download.id, [.failed, .completed])
        #expect(failed.state == .failed)
        #expect(failed.failure == .http(status: 503))

        try await scheduler.networkAvailable()
        let done = try await wait(for: download.id, [.completed, .failed])
        #expect(done.state == .completed)
        #expect(try finalBytes(done) == RocketTestServer.content(count: size))
    }

    @Test func rejectsNonHTTPURLs() async throws {
        await #expect(throws: DownloadError.invalidURL) {
            _ = try await scheduler.add(url: URL(string: "file:///etc/passwd")!, folder: folder)
        }
    }
}
