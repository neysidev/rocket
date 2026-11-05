import RocketCore
import RocketEngine
import RocketIPC
import XPC

/// Handles messages from one connected client (app, CLI, extension host).
struct AgentPeerHandler: XPCPeerHandler {
    let scheduler: DownloadScheduler

    func handleIncomingRequest(_ message: XPCReceivedMessage) -> (any Encodable)? {
        let envelope: Envelope<Command>
        do {
            envelope = try message.decode()
        } catch {
            return Envelope(Reply.error("Malformed message"))
        }
        guard envelope.apiVersion.major == RocketAPI.version.major else {
            return Envelope(Reply.error("Unsupported API version \(envelope.apiVersion.major)"))
        }
        // Reply asynchronously so the scheduler actor can be awaited.
        let pending = PendingReply(message: message)
        Task {
            pending.message.reply(Envelope(await handle(envelope.payload)))
        }
        return nil
    }

    /// XPC objects are thread-safe and a message is replied to exactly once, so crossing into the Task is safe.
    private struct PendingReply: @unchecked Sendable {
        let message: XPCReceivedMessage
    }

    private func handle(_ command: Command) async -> Reply {
        do {
            switch command {
            case .snapshot:
                return .snapshot(try await scheduler.snapshot())
            case .add, .pause, .resume, .cancel:
                return .error("Not implemented yet")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
