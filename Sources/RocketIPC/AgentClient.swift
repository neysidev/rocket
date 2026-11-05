import Foundation
import os
import XPC

public enum AgentClientError: Error, Sendable {
    /// The agent did not answer in time (not running, not approved, or blocked by launchd).
    case timedOut
    /// The XPC session failed (concurrent use, agent crashed, or service unavailable).
    case connectionFailed
}

extension AgentClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .timedOut, .connectionFailed:
            String(localized: "Could not reach Rocket's background service. Open Settings → Login Items and make sure Rocket is allowed to run in the background.")
        }
    }
}

/// Sends commands to the agent; `AgentClient` over XPC, fakes in tests.
public protocol AgentCommanding: Sendable {
    func send(_ command: Command) async throws -> Reply
}

/// One in-flight XPC request at a time; overlapping `send` calls corrupt the session.
private actor XPCSendGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// XPC client used by the app and CLI to talk to `rocketd`.
public final class AgentClient: AgentCommanding {
    private let session: XPCSession
    private let gate = XPCSendGate()

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
        try await gate.withLock {
            try await self.sendUnlocked(command, timeout: timeout)
        }
    }

    private func sendUnlocked(_ command: Command, timeout: Duration) async throws -> Reply {
        // XPC keeps a reply pending while launchd cannot start the agent, and cancelling the session does
        // not fail it, so the timeout resumes the continuation itself. The lock makes sure only one side does.
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let session = self.session
        return try await withCheckedThrowingContinuation { continuation in
            let resume: @Sendable (Result<Reply, any Error>, Bool) -> Void = { result, invalidateSession in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                guard first else { return }
                if invalidateSession { session.cancel(reason: "Timed out") }
                continuation.resume(with: result.mapError(Self.map))
            }
            do {
                try session.send(Envelope(command)) { (result: Result<Envelope<Reply>, any Error>) in
                    resume(result.map(\.payload).mapError(Self.map), false)
                }
            } catch {
                resume(.failure(Self.map(error)), false)
            }
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                resume(.failure(AgentClientError.timedOut), true)
            }
        }
    }

    private static func map(_ error: any Error) -> any Error {
        if error is AgentClientError { return error }
        let ns = error as NSError
        if ns.domain.contains("XPC") { return AgentClientError.connectionFailed }
        return error
    }
}

/// Long-lived app connection: opens a fresh XPC session after transport failures (the CLI creates a new client per command).
public final class ReconnectingAgentClient: AgentCommanding {
    private let gate = XPCSendGate()
    private let client = OSAllocatedUnfairLock<AgentClient?>(initialState: nil)

    public init() {}

    public func send(_ command: Command) async throws -> Reply {
        try await gate.withLock {
            for attempt in 0..<2 {
                do {
                    let connection = try self.connection()
                    return try await connection.send(command)
                } catch {
                    discard()
                    guard attempt == 0, Self.isRecoverable(error) else { throw error }
                }
            }
            throw AgentClientError.connectionFailed
        }
    }

    private func connection() throws -> AgentClient {
        try client.withLock { cached in
            if let cached { return cached }
            let fresh = try AgentClient()
            cached = fresh
            return fresh
        }
    }

    private func discard() {
        client.withLock { cached in
            cached = nil
        }
    }

    private static func isRecoverable(_ error: any Error) -> Bool {
        error is AgentClientError || (error as NSError).domain.contains("XPC")
    }
}
