import Foundation
import GRDB
import RocketCore

/// The agent's SQLite database (WAL). Only `rocketd` opens it.
public struct RocketDatabase: Sendable {
    public let writer: any DatabaseWriter

    /// On-disk database at `Rocket.supportDirectory/rocket.sqlite`.
    public static func onDisk(at url: URL = Rocket.supportDirectory.appending(path: "rocket.sqlite")) throws -> RocketDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try RocketDatabase(writer: DatabasePool(path: url.path))
    }

    /// In-memory database for tests.
    public static func inMemory() throws -> RocketDatabase {
        try RocketDatabase(writer: DatabaseQueue())
    }

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Append-only. Never edit a migration after it ships.
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1_createSchema") { db in
            try db.create(table: "queue") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("maxActive", .integer).notNull().defaults(to: 3)
                t.column("scheduleJSON", .text)
                t.column("postAction", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: "INSERT INTO queue (id, name) VALUES ('default', 'Default')")

            try db.create(table: "download") { t in
                t.column("id", .text).primaryKey()
                t.column("url", .text).notNull()
                t.column("finalURL", .text)
                t.column("destinationPath", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("totalBytes", .integer)
                t.column("state", .text).notNull()
                t.column("queueId", .text).notNull().defaults(to: "default").references("queue")
                t.column("connections", .integer).notNull().defaults(to: 8)
                t.column("speedLimit", .integer)
                t.column("etag", .text)
                t.column("lastModified", .text)
                t.column("checksumKind", .text)
                t.column("checksum", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
                t.column("errorCode", .text)
            }
            try db.create(table: "segment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("downloadId", .text).notNull().indexed().references("download", onDelete: .cascade)
                t.column("start", .integer).notNull()
                t.column("end", .integer).notNull()
                t.column("received", .integer).notNull().defaults(to: 0)
                t.column("state", .text).notNull()
            }
            try db.create(table: "rule") { t in
                t.column("id", .text).primaryKey()
                t.column("matchJSON", .text).notNull()
                t.column("actionJSON", .text).notNull()
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("enabled", .boolean).notNull().defaults(to: true)
            }
            try db.create(table: "requestContext") { t in
                t.primaryKey("downloadId", .text).references("download", onDelete: .cascade)
                t.column("headersJSON", .text)
                t.column("cookiesRef", .text) // Keychain reference, never the cookie itself
                t.column("referrer", .text)
                t.column("userAgent", .text)
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("valueJSON", .text).notNull()
            }
        }
        m.registerMigration("v2_resumeState") { db in
            try db.alter(table: "download") { t in
                t.add(column: "acceptsRanges", .boolean).notNull().defaults(to: false)
                t.add(column: "receivedBytes", .integer).notNull().defaults(to: 0)
                t.add(column: "failure", .text) // JSON-encoded DownloadError
            }
        }
        return m
    }
}
