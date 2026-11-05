import Foundation
import RocketCore
import RocketPersistence
import Testing

@Test func migratesAndRoundTripsDownload() async throws {
    let repo = GRDBDownloadRepository(db: try .inMemory())
    let download = Download(url: URL(string: "https://example.com/a.iso")!, destinationPath: "/tmp", fileName: "a.iso")
    try await repo.save(download)
    #expect(try await repo.all().map(\.id) == [download.id])
    try await repo.delete(id: download.id)
    #expect(try await repo.all().isEmpty)
}
