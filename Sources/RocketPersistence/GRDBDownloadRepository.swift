import Foundation
import GRDB
import RocketCore

extension Download: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "download"
}

/// GRDB adapter for `DownloadRepository`.
public struct GRDBDownloadRepository: DownloadRepository {
    private let db: RocketDatabase

    public init(db: RocketDatabase) {
        self.db = db
    }

    public func all() async throws -> [Download] {
        try await db.writer.read { try Download.order(Column("createdAt").desc).fetchAll($0) }
    }

    public func save(_ download: Download) async throws {
        try await db.writer.write { try download.save($0) }
    }

    public func delete(id: UUID) async throws {
        _ = try await db.writer.write { try Download.deleteOne($0, id: id) }
    }
}
