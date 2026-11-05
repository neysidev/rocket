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
    case add(url: URL, directory: String?)
    case pause(id: UUID)
    case resume(id: UUID)
    case cancel(id: UUID)
    case snapshot
}

public enum Reply: Codable, Sendable {
    case ok
    case snapshot([Download])
    case error(String)
}
