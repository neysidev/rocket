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

    // Synchronous GRDB calls on purpose: the scheduler records pause/cancel from tasks that were just
    // cancelled, and GRDB's async accessors refuse to start in a cancelled task. Each call touches a few rows.

    public func all() async throws -> [Download] {
        try read { try Download.order(Column("createdAt").desc).fetchAll($0) }
    }

    public func download(id: UUID) async throws -> Download? {
        try read { try Download.fetchOne($0, id: id) }
    }

    public func save(_ download: Download) async throws {
        try write { try download.save($0) }
    }

    public func delete(id: UUID) async throws {
        try write { _ = try Download.deleteOne($0, id: id) }
    }

    private func read<T>(_ body: (Database) throws -> T) throws -> T {
        try db.writer.read(body)
    }

    private func write(_ body: (Database) throws -> Void) throws {
        try db.writer.write(body)
    }

    // MARK: CheckpointStore

    public func saveCheckpoint(downloadID: UUID, segments: [Segment]) async throws {
        try write { db in
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
        try read { db in
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

extension DownloadQueue: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "queue"
}

extension GRDBDownloadRepository: QueueRepository {
    public func queues() async throws -> [DownloadQueue] {
        try read { try DownloadQueue.order(Column("sortOrder"), Column("name")).fetchAll($0) }
    }

    public func save(_ queue: DownloadQueue) async throws {
        try write { try queue.save($0) }
    }

    /// The default queue cannot be deleted; a deleted queue's downloads move to it.
    public func deleteQueue(id: String) async throws {
        guard id != DownloadQueue.defaultID else { return }
        try write { db in
            try db.execute(sql: "UPDATE download SET queueId = ? WHERE queueId = ?", arguments: [DownloadQueue.defaultID, id])
            _ = try DownloadQueue.deleteOne(db, key: id)
        }
    }
}
