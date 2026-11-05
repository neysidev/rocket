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
