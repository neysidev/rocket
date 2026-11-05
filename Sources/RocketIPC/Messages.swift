import Foundation
import RocketCore

/// Public, versioned contract between `rocketd` and its clients (app, CLI, extensions).
public enum RocketAPI {
    /// Bump major only with an ADR. Minor versions add optional fields only.
    public static let version = APIVersion(major: 1, minor: 0)
    /// Mach service name; the Team ID prefix is added at signing time.
    public static let machServiceName = "\(Rocket.bundleID).agent"
}

public struct APIVersion: Codable, Sendable, Hashable {
    public var major: Int
    public var minor: Int
}

/// Every message carries the API version.
public struct Envelope<Payload: Codable & Sendable>: Codable, Sendable {
    public var apiVersion: APIVersion
    public var payload: Payload

    public init(_ payload: Payload, apiVersion: APIVersion = RocketAPI.version) {
        self.apiVersion = apiVersion
        self.payload = payload
    }
}

public enum Command: Codable, Sendable, Hashable {
    /// `directory` defaults to ~/Downloads; `fileName` to what the server suggests.
    case add(
        url: URL, directory: String?, fileName: String? = nil, connections: Int? = nil, speedLimit: Int64? = nil,
        queueID: String? = nil, context: RequestContext? = nil
    )
    /// Replace an expired link, keeping progress (FR-ENG-09).
    case refreshURL(id: UUID, url: URL)
    case pause(id: UUID)
    case resume(id: UUID)
    case cancel(id: UUID)
    case remove(id: UUID, deleteFile: Bool)
    case snapshot
    /// Bytes per second, nil = unlimited. `downloadID` nil sets the global limit.
    case setLimit(downloadID: UUID?, bytesPerSecond: Int64?)
    case details(id: UUID)
    case rules
    case saveRule(DownloadRule)
    case deleteRule(id: String)
    case queues
    case saveQueue(DownloadQueue)
    case deleteQueue(id: String)
    /// Moves downloads into a queue, before another download or at the end (FR-QUE-03).
    case move(ids: [UUID], toQueue: String, before: UUID?)
    /// Looks up name, size and range support without adding anything (FR-ADD-02).
    case probe(url: URL, context: RequestContext? = nil)
}

public enum Reply: Codable, Sendable {
    case ok
    case download(Download)
    case info(RemoteFileInfo)
    case queues([DownloadQueue])
    case rules([DownloadRule])
    case details(DownloadDetails)
    case snapshot([Download])
    case error(String)
}
