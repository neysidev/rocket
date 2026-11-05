import Foundation
import XPC

/// XPC client used by the app and CLI to talk to `rocketd`.
public final class AgentClient: Sendable {
    private let session: XPCSession

    public init() throws {
        session = try XPCSession(machService: RocketAPI.machServiceName)
    }

    deinit {
        session.cancel(reason: "Client released")
    }

    public func send(_ command: Command) async throws -> Reply {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(Envelope(command)) { (result: Result<Envelope<Reply>, any Error>) in
                    continuation.resume(with: result.map(\.payload))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
