import Foundation

/// A download as stored by the agent and shown to clients.
public struct Download: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var url: URL
    public var destinationPath: String
    public var fileName: String
    public var totalBytes: Int64?
    public var state: DownloadState
    public var connections: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        destinationPath: String,
        fileName: String,
        totalBytes: Int64? = nil,
        state: DownloadState = .queued,
        connections: Int = 8,
        createdAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.destinationPath = destinationPath
        self.fileName = fileName
        self.totalBytes = totalBytes
        self.state = state
        self.connections = connections
        self.createdAt = createdAt
    }
}

/// Persistence port; GRDB adapter lives in RocketPersistence.
public protocol DownloadRepository: Sendable {
    func all() async throws -> [Download]
    func save(_ download: Download) async throws
    func delete(id: UUID) async throws
}
