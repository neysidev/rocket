import Foundation

/// A download as stored by the agent and shown to clients.
public struct Download: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var url: URL
    /// Folder the file lands in.
    public var destinationPath: String
    public var fileName: String
    public var state: DownloadState
    public var connections: Int
    public var queueID: String
    /// Order within the queue (FR-QUE-03); lower runs first.
    public var position: Double
    public var createdAt: Date
    public var completedAt: Date?

    // What the probe learned; needed to resume safely.
    public var finalURL: URL?
    public var totalBytes: Int64?
    public var acceptsRanges: Bool
    public var etag: String?
    public var lastModified: String?

    public var receivedBytes: Int64
    /// Per-download cap in bytes per second (FR-SPD-02); nil = only the global limit applies.
    public var speedLimit: Int64?
    /// Why the download failed, or why it was restarted (e.g. `.remoteFileChanged`).
    public var failure: DownloadError?

    public init(
        id: UUID = UUID(),
        url: URL,
        destinationPath: String,
        fileName: String,
        state: DownloadState = .queued,
        connections: Int = 8,
        createdAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.destinationPath = destinationPath
        self.fileName = fileName
        self.state = state
        self.connections = connections
        self.createdAt = createdAt
        queueID = DownloadQueue.defaultID
        position = createdAt.timeIntervalSinceReferenceDate
        acceptsRanges = false
        receivedBytes = 0
    }

    /// The probe result as stored, used to resume without probing again.
    public var remoteInfo: RemoteFileInfo {
        get {
            RemoteFileInfo(
                finalURL: finalURL ?? url, totalBytes: totalBytes, acceptsRanges: acceptsRanges,
                etag: etag, lastModified: lastModified, suggestedFileName: fileName
            )
        }
        set {
            finalURL = newValue.finalURL
            totalBytes = newValue.totalBytes
            acceptsRanges = newValue.acceptsRanges
            etag = newValue.etag
            lastModified = newValue.lastModified
        }
    }

    /// `<destination>/<fileName>.rocketpart`
    public var partFileURL: URL {
        URL(filePath: destinationPath, directoryHint: .isDirectory).appending(path: fileName + ".rocketpart")
    }

    public var fileURL: URL {
        URL(filePath: destinationPath, directoryHint: .isDirectory).appending(path: fileName)
    }
}

extension Download {
    enum CodingKeys: String, CodingKey {
        case id, url, destinationPath, fileName, state, connections, position, createdAt, completedAt
        case finalURL, totalBytes, acceptsRanges, etag, lastModified, receivedBytes, speedLimit, failure
        case queueID = "queueId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(URL.self, forKey: .url)
        destinationPath = try c.decode(String.self, forKey: .destinationPath)
        fileName = try c.decode(String.self, forKey: .fileName)
        state = try c.decode(DownloadState.self, forKey: .state)
        connections = try c.decode(Int.self, forKey: .connections)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Older encodings (IPC from a previous minor version) may lack these.
        queueID = try c.decodeIfPresent(String.self, forKey: .queueID) ?? DownloadQueue.defaultID
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? createdAt.timeIntervalSinceReferenceDate
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        finalURL = try c.decodeIfPresent(URL.self, forKey: .finalURL)
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes)
        acceptsRanges = try c.decodeIfPresent(Bool.self, forKey: .acceptsRanges) ?? false
        etag = try c.decodeIfPresent(String.self, forKey: .etag)
        lastModified = try c.decodeIfPresent(String.self, forKey: .lastModified)
        receivedBytes = try c.decodeIfPresent(Int64.self, forKey: .receivedBytes) ?? 0
        speedLimit = try c.decodeIfPresent(Int64.self, forKey: .speedLimit)
        failure = try c.decodeIfPresent(DownloadError.self, forKey: .failure)
    }
}

/// Persistence port; the GRDB adapter lives in RocketPersistence.
public protocol DownloadRepository: Sendable {
    func all() async throws -> [Download]
    func download(id: UUID) async throws -> Download?
    func save(_ download: Download) async throws
    func delete(id: UUID) async throws
}

/// Durable per-segment progress. Offsets are saved only after their bytes are fsynced.
public protocol CheckpointStore: Sendable {
    func saveCheckpoint(downloadID: UUID, segments: [Segment]) async throws
    func segments(downloadID: UUID) async throws -> [Segment]
}

/// One line of a download's log: state changes, retries, back-offs, failures (TRD: per-download log).
public struct LogEntry: Codable, Sendable, Hashable {
    public var date: Date
    public var message: String
    public var isError: Bool

    public init(date: Date = .now, message: String, isError: Bool = false) {
        self.date = date
        self.message = message
        self.isError = isError
    }
}

/// What the detail view shows beyond the list row (FR-APP-02).
public struct DownloadDetails: Codable, Sendable, Hashable {
    public var segments: [Segment]
    public var activeConnections: Int
    /// Current limit after any rate-limit back-off; nil when not running.
    public var connectionLimit: Int?
    public var log: [LogEntry]

    public init(segments: [Segment], activeConnections: Int, connectionLimit: Int?, log: [LogEntry]) {
        self.segments = segments
        self.activeConnections = activeConnections
        self.connectionLimit = connectionLimit
        self.log = log
    }
}
