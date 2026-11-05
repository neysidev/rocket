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
            case let .add(url, directory, fileName, connections, speedLimit):
                // Unset options follow the app's settings.
                let defaults = RocketDefaults()
                let folder = directory.map { URL(filePath: ($0 as NSString).expandingTildeInPath, directoryHint: .isDirectory) }
                    ?? defaults.folder
                return .download(try await scheduler.add(
                    url: url, folder: folder, fileName: fileName, connections: connections ?? defaults.connections,
                    speedLimit: speedLimit
                ))
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
            case .probe(let url):
                return .info(try await scheduler.probe(url))
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
        default: error.localizedDescription
        }
    }
}
