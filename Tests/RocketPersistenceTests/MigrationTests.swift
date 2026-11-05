import Foundation
import RocketCore
import RocketPersistence
import Testing

@Test func migratesAndRoundTripsDownload() async throws {
    let repo = GRDBDownloadRepository(db: try .inMemory())
    var download = Download(url: URL(string: "https://example.com/a.iso")!, destinationPath: "/tmp", fileName: "a.iso")
    download.remoteInfo = RemoteFileInfo(
        finalURL: URL(string: "https://cdn.example.com/a.iso")!, totalBytes: 42, acceptsRanges: true, etag: "\"e\""
    )
    download.failure = .remoteFileChanged
    download.createdAt = Date(timeIntervalSince1970: 1_700_000_000) // SQLite keeps milliseconds only
    try await repo.save(download)
    #expect(try await repo.download(id: download.id) == download)
    try await repo.delete(id: download.id)
    #expect(try await repo.all().isEmpty)
}

@Test func checkpointsReplaceSegmentsAndUpdateProgress() async throws {
    let repo = GRDBDownloadRepository(db: try .inMemory())
    let download = Download(url: URL(string: "https://example.com/a.iso")!, destinationPath: "/tmp", fileName: "a.iso")
    try await repo.save(download)

    try await repo.saveCheckpoint(downloadID: download.id, segments: [Segment(start: 0, end: 99, received: 10)])
    let segments = [Segment(start: 0, end: 49, received: 50), Segment(start: 50, end: 99, received: 20)]
    try await repo.saveCheckpoint(downloadID: download.id, segments: segments)

    #expect(try await repo.segments(downloadID: download.id) == segments)
    #expect(try await repo.download(id: download.id)?.receivedBytes == 70)
}

@Test func queuesPersistWithScheduleAndDeleteMovesDownloads() async throws {
    let repo = GRDBDownloadRepository(db: try .inMemory())
    #expect(try await repo.queues().map(\.id) == ["default"]) // created by v1 migration
    let night = DownloadQueue(id: "night", name: "Night", maxActive: 2, schedule: QueueSchedule(start: 60, stop: 420, weekdays: [2, 3]), postAction: .sleep, speedLimit: 1_000_000, sortOrder: 1)
    try await repo.save(night)
    #expect(try await repo.queues().last == night)

    var download = Download(url: URL(string: "https://example.com/a")!, destinationPath: "/tmp", fileName: "a")
    download.queueID = "night"
    try await repo.save(download)
    try await repo.deleteQueue(id: "night")
    try await repo.deleteQueue(id: "default") // ignored
    #expect(try await repo.queues().map(\.id) == ["default"])
    #expect(try await repo.download(id: download.id)?.queueID == "default")
}

@Test func rulesRoundTrip() async throws {
    let repo = GRDBDownloadRepository(db: try .inMemory())
    let rule = DownloadRule(name: "ISOs", priority: 3, match: RuleMatch(domains: ["ubuntu.com"], extensions: ["iso"], minBytes: 1), action: RuleAction(queueID: "night", connections: 2))
    try await repo.save(rule)
    #expect(try await repo.rules() == [rule])
    try await repo.deleteRule(id: rule.id)
    #expect(try await repo.rules().isEmpty)
}
