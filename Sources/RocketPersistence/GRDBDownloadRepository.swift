import Foundation
import GRDB
import RocketCore

extension Download: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "download"
}

/// GRDB adapter for `DownloadRepository` and `CheckpointStore`.
public struct GRDBDownloadRepository: DownloadRepository, CheckpointStore {
    private let db: RocketDatabase

    public init(db: RocketDatabase) {
        self.db = db
    }

    public func all() async throws -> [Download] {
        try await db.writer.read { try Download.order(Column("createdAt").desc).fetchAll($0) }
    }

    public func download(id: UUID) async throws -> Download? {
        try await db.writer.read { try Download.fetchOne($0, id: id) }
    }

    public func save(_ download: Download) async throws {
        try await db.writer.write { try download.save($0) }
    }

    public func delete(id: UUID) async throws {
        _ = try await db.writer.write { try Download.deleteOne($0, id: id) }
    }

    // MARK: CheckpointStore

    /// Synchronous on purpose: the final checkpoint runs while the download task is being cancelled,
    /// and GRDB's async accessors refuse to start in a cancelled task. The write is a few rows.
    public func saveCheckpoint(downloadID: UUID, segments: [Segment]) async throws {
        try writeCheckpoint(downloadID: downloadID, segments: segments)
    }

    private func writeCheckpoint(downloadID: UUID, segments: [Segment]) throws {
        try db.writer.write { db in
            try SegmentRecord.filter(Column("downloadId") == downloadID).deleteAll(db)
            for segment in segments {
                try SegmentRecord(downloadId: downloadID, segment: segment).insert(db)
            }
            try Download.filter(id: downloadID).updateAll(
                db, Column("receivedBytes").set(to: segments.reduce(0) { $0 + $1.received })
            )
        }
    }

    public func segments(downloadID: UUID) async throws -> [Segment] {
        try await db.writer.read { db in
            try SegmentRecord.filter(Column("downloadId") == downloadID).order(Column("id")).fetchAll(db).map(\.segment)
        }
    }
}

private struct SegmentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "segment"
    var id: Int64?
    var downloadId: UUID
    var start: Int64
    var end: Int64
    var received: Int64
    var state: String

    init(downloadId: UUID, segment: Segment) {
        self.downloadId = downloadId
        start = segment.start
        end = segment.end
        received = segment.received
        state = segment.isComplete ? "complete" : "pending"
    }

    var segment: Segment { Segment(start: start, end: end, received: received) }
}
