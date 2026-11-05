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
