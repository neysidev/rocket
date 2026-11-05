import ArgumentParser
import RocketIPC

/// Exit codes: 0 ok, 1 failed, 2 usage, 3 agent unavailable, 4 checksum mismatch.
@main
struct RocketCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rocket",
        abstract: "Fast, resumable downloads from the terminal.",
        version: "API \(RocketAPI.version.major).\(RocketAPI.version.minor)"
    )

    func run() throws {
        print("Agent connection not implemented yet (\(RocketAPI.machServiceName)).")
        throw ExitCode(3)
    }
}

