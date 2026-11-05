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
    case add(url: URL, directory: String?, fileName: String? = nil, connections: Int? = nil, speedLimit: Int64? = nil)
    case pause(id: UUID)
    case resume(id: UUID)
    case cancel(id: UUID)
    case remove(id: UUID, deleteFile: Bool)
    case snapshot
    /// Bytes per second, nil = unlimited. `downloadID` nil sets the global limit.
    case setLimit(downloadID: UUID?, bytesPerSecond: Int64?)
    /// Looks up name, size and range support without adding anything (FR-ADD-02).
    case probe(url: URL)
}

public enum Reply: Codable, Sendable {
    case ok
    case download(Download)
    case info(RemoteFileInfo)
    case snapshot([Download])
    case error(String)
}
