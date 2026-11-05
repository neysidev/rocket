import Foundation
import os
import XPC

public enum AgentClientError: Error, Sendable {
    /// The agent did not answer in time (not running, not approved, or blocked by launchd).
    case timedOut
}

/// Sends commands to the agent; `AgentClient` over XPC, fakes in tests.
public protocol AgentCommanding: Sendable {
    func send(_ command: Command) async throws -> Reply
}

/// XPC client used by the app and CLI to talk to `rocketd`.
public final class AgentClient: AgentCommanding {
    private let session: XPCSession

    public init() throws {
        session = try XPCSession(machService: RocketAPI.machServiceName)
    }

    deinit {
        session.cancel(reason: "Client released")
    }

    public func send(_ command: Command) async throws -> Reply {
        try await send(command, timeout: .seconds(45))
    }

    /// Sends a command and waits for the reply. After a timeout the session is cancelled; create a new client.
    public func send(_ command: Command, timeout: Duration) async throws -> Reply {
        // XPC keeps a reply pending while launchd cannot start the agent, and cancelling the session does
        // not fail it, so the timeout resumes the continuation itself. The lock makes sure only one side does.
        let resumed = OSAllocatedUnfairLock(initialState: false)
        return try await withCheckedThrowingContinuation { continuation in
            let resume: @Sendable (Result<Reply, any Error>) -> Void = { result in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
            }
            do {
                try session.send(Envelope(command)) { (result: Result<Envelope<Reply>, any Error>) in
                    resume(result.map(\.payload))
                }
            } catch {
                resume(.failure(error))
            }
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [session] in
                resume(.failure(AgentClientError.timedOut))
                session.cancel(reason: "Timed out")
            }
        }
    }
}
