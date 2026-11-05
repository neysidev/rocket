import ArgumentParser
import Foundation
import RocketIPC

/// Exit codes: 0 ok, 1 failed, 2 usage, 3 agent unavailable, 4 checksum mismatch.
@main
struct RocketCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rocket",
        abstract: "Fast, resumable downloads from the terminal.",
        version: "API \(RocketAPI.version.major).\(RocketAPI.version.minor)",
        subcommands: [List.self]
    )
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List downloads.")

    func run() async throws {
        let reply: Reply
        do {
            reply = try await AgentClient().send(.snapshot)
        } catch {
            FileHandle.standardError.write(Data("Rocket agent unavailable: \(error.localizedDescription)\n".utf8))
            throw ExitCode(3)
        }
        switch reply {
        case .snapshot(let downloads):
            if downloads.isEmpty { print("No downloads.") }
            for download in downloads {
                print("\(download.state.rawValue)\t\(download.fileName)\t\(download.url.absoluteString)")
            }
        case .error(let message):
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            throw ExitCode(1)
        case .ok:
            break
        }
    }
}
