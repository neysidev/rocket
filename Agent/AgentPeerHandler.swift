import Foundation
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
            case let .add(url, directory, fileName, connections, speedLimit, queueID, context):
                // Unset options come from rules, then the app's settings (resolved by the scheduler).
                let folder = directory.map { URL(filePath: ($0 as NSString).expandingTildeInPath, directoryHint: .isDirectory) }
                return .download(try await scheduler.add(
                    url: url, folder: folder, fileName: fileName, connections: connections, speedLimit: speedLimit,
                    queueID: queueID, context: context
                ))
            case let .refreshURL(id, url):
                return .download(try await scheduler.refreshURL(id: id, to: url))
            case .pause(let id):
                try await scheduler.pause(id: id)
                return .ok
            case .resume(let id):
                try await scheduler.resume(id: id)
                return .ok
            case .cancel(let id):
                try await scheduler.cancel(id: id)
                return .ok
            case let .remove(id, deleteFile):
                try await scheduler.remove(id: id, deleteFile: deleteFile)
                return .ok
            case let .setLimit(id, bytesPerSecond):
                try await scheduler.setLimit(id: id, bytesPerSecond: bytesPerSecond)
                return .ok
            case .details(let id):
                return .details(try await scheduler.details(id: id))
            case .rules:
                return .rules(try await scheduler.rules())
            case .saveRule(let rule):
                try await scheduler.saveRule(rule)
                return .ok
            case .deleteRule(let id):
                try await scheduler.deleteRule(id: id)
                return .ok
            case .queues:
                return .queues(try await scheduler.queues())
            case .saveQueue(let queue):
                try await scheduler.saveQueue(queue)
                return .ok
            case .deleteQueue(let id):
                try await scheduler.deleteQueue(id: id)
                return .ok
            case let .move(ids, queueID, before):
                try await scheduler.move(ids: ids, toQueue: queueID, before: before)
                return .ok
            case let .probe(url, context):
                return .info(try await scheduler.probe(url, context: context))
            case .snapshot:
                return .snapshot(try await scheduler.snapshot())
            }
        } catch {
            return .error(Self.describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case let error as DownloadError: error.userMessage
        case SchedulerError.notFound(let id): "No download with id \(id)"
        case RefreshError.differentFile: "That link points to a different file (the size does not match)."
        case RequestContextError.invalidHeaderName(let name): "Invalid header name: \(name)"
        case RequestContextError.invalidHeaderValue(let name): "Header \(name) contains a line break."
        default: error.localizedDescription
        }
    }
}
