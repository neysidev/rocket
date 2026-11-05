import ArgumentParser
import Foundation
import RocketCore
import RocketIPC

/// Exit codes: 0 ok, 1 failed, 2 usage, 3 agent unavailable, 4 checksum mismatch.
@main
struct RocketCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rocket",
        abstract: "Fast, resumable downloads from the terminal.",
        version: "API \(RocketAPI.version.major).\(RocketAPI.version.minor)",
        subcommands: [Add.self, Info.self, List.self, Limit.self, Pause.self, Resume.self, Cancel.self]
    )

    /// Same as ArgumentParser's default, but usage errors exit 2 (TRD) instead of 64.
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            if exitCode(for: error) == .validationFailure {
                FileHandle.standardError.write(Data((fullMessage(for: error) + "\n").utf8))
                Foundation.exit(2)
            }
            exit(withError: error)
        }
    }
}

// MARK: Commands

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add a download.")

    @Argument(help: "http or https URL.") var url: String
    @Option(help: "Destination folder (default: ~/Downloads).") var dir: String?
    @Option(help: "File name (default: the server's).") var name: String?
    @Option(help: "Parallel connections, 1–16.") var connections: Int?
    @Option(help: "Speed limit for this download, e.g. 2M or 500K (bytes per second).") var limit: String?
    @Flag(help: "Wait until the download finishes; exit 1 if it fails.") var wait = false
    @Flag(help: "Print JSON.") var json = false

    func validate() throws {
        guard URL(string: url)?.scheme != nil else { throw ValidationError("Not a URL: \(url)") }
        if let connections, !(1...16).contains(connections) { throw ValidationError("--connections must be 1–16") }
        if let limit, ByteRate.parse(limit) == nil { throw ValidationError("Not a speed: \(limit). Try 2M or 500K.") }
    }

    func run() async throws {
        let directory = dir.map { URL(filePath: $0, relativeTo: .currentDirectory()).path }
        let reply = try await Agent.send(.add(
            url: URL(string: url)!, directory: directory, fileName: name, connections: connections,
            speedLimit: limit.flatMap(ByteRate.parse)
        ))
        guard case .download(let download) = reply else { throw Agent.unexpected(reply) }
        guard wait else { return Output.print(download, json: json) }
        let finished = try await Agent.waitForEnd(of: download.id)
        Output.print(finished, json: json)
        if finished.state != .completed { throw ExitCode.failure }
    }
}

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what the server reports about a URL without downloading.")
    @Argument(help: "http or https URL.") var url: String
    @Flag(help: "Print JSON.") var json = false

    func run() async throws {
        guard let url = URL(string: url) else { throw ValidationError("Not a URL: \(self.url)") }
        guard case .info(let info) = try await Agent.send(.probe(url: url)) else { throw ExitCode.failure }
        if json { return Output.printJSON(info) }
        print("Name:       \(info.suggestedFileName ?? "-")")
        print("Size:       \(info.totalBytes.map(Output.bytes) ?? "unknown")")
        print("Type:       \(info.contentType ?? "-")")
        print("Resumable:  \(info.acceptsRanges ? "yes" : "no (single connection)")")
        if info.finalURL != url { print("Redirects:  \(info.finalURL.absoluteString)") }
    }
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List downloads.")
    @Flag(help: "Print JSON.") var json = false

    func run() async throws {
        let downloads = try await Agent.snapshot()
        if json { return Output.printJSON(downloads) }
        if downloads.isEmpty { return print("No downloads.") }
        downloads.forEach { Output.print($0, json: false) }
    }
}

struct Limit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Set the speed limit for all downloads, or for one with --id.")
    @Argument(help: "Bytes per second, e.g. 2M, 500K, 1.5G, or \"off\".") var rate: String
    @Option(help: "Download ID or a unique prefix of it.") var id: String?

    func validate() throws {
        if rate.lowercased() != "off", ByteRate.parse(rate) == nil { throw ValidationError("Not a speed: \(rate). Try 2M or 500K.") }
    }

    func run() async throws {
        let bytes = rate.lowercased() == "off" ? nil : ByteRate.parse(rate)
        let target: UUID? = if let id { try await Agent.resolve(id) } else { nil }
        try await Agent.expectOK(.setLimit(downloadID: target, bytesPerSecond: bytes))
    }
}

struct Pause: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Pause a download.")
    @Argument(help: "Download ID or a unique prefix of it.") var id: String
    func run() async throws { try await Agent.expectOK(.pause(id: Agent.resolve(id))) }
}

struct Resume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Resume a paused or failed download.")
    @Argument(help: "Download ID or a unique prefix of it.") var id: String
    func run() async throws { try await Agent.expectOK(.resume(id: Agent.resolve(id))) }
}

struct Cancel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Cancel a download and delete its partial file.")
    @Argument(help: "Download ID or a unique prefix of it.") var id: String
    func run() async throws { try await Agent.expectOK(.cancel(id: Agent.resolve(id))) }
}

// MARK: Agent

enum Agent {
    static func send(_ command: Command) async throws -> Reply {
        let reply: Reply
        do {
            reply = try await AgentClient().send(command)
        } catch {
            Output.error("Rocket agent unavailable. Open Rocket Downloader once to set it up. (\(error.localizedDescription))")
            throw ExitCode(3)
        }
        if case .error(let message) = reply {
            Output.error(message)
            throw ExitCode.failure
        }
        return reply
    }

    static func expectOK(_ command: Command) async throws {
        let reply = try await send(command)
        guard case .ok = reply else { throw unexpected(reply) }
    }

    static func snapshot() async throws -> [Download] {
        let reply = try await send(.snapshot)
        guard case .snapshot(let downloads) = reply else { throw unexpected(reply) }
        return downloads
    }

    /// Full UUID, or a prefix that matches exactly one download.
    static func resolve(_ text: String) async throws -> UUID {
        if let id = UUID(uuidString: text) { return id }
        let matches = try await snapshot().filter { $0.id.uuidString.lowercased().hasPrefix(text.lowercased()) }
        guard matches.count == 1 else {
            throw ValidationError(matches.isEmpty ? "No download matches \(text)" : "\(text) matches \(matches.count) downloads")
        }
        return matches[0].id
    }

    /// Polls until the download completes, fails or is cancelled, drawing progress on stderr.
    static func waitForEnd(of id: UUID) async throws -> Download {
        while true {
            guard let download = try await snapshot().first(where: { $0.id == id }) else {
                throw ValidationError("Download \(id) disappeared")
            }
            if [.completed, .failed, .cancelled].contains(download.state) {
                Output.clearProgress()
                return download
            }
            Output.progress(download)
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    static func unexpected(_ reply: Reply) -> any Error {
        Output.error("Unexpected reply from agent: \(reply)")
        return ExitCode.failure
    }
}

// MARK: Output

enum Output {
    static func print(_ download: Download, json: Bool) {
        if json { return printJSON(download) }
        let progress = download.totalBytes.map { total in
            total > 0 ? "\(Int(Double(download.receivedBytes) / Double(total) * 100))%" : "100%"
        } ?? bytes(download.receivedBytes)
        var line = "\(download.id.uuidString.prefix(8).lowercased())  \(download.state.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) "
        line += "\(progress.padding(toLength: 6, withPad: " ", startingAt: 0))  \(download.fileName)"
        if let failure = download.failure { line += "  (\(failure))" }
        Swift.print(line)
    }

    static func printJSON(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) { Swift.print(String(decoding: data, as: UTF8.self)) }
    }

    static func progress(_ download: Download) {
        guard isatty(STDERR_FILENO) == 1 else { return }
        let total = download.totalBytes.map { " of \(bytes($0))" } ?? ""
        FileHandle.standardError.write(Data("\r\u{1B}[K\(download.state.rawValue) \(bytes(download.receivedBytes))\(total)".utf8))
    }

    static func clearProgress() {
        guard isatty(STDERR_FILENO) == 1 else { return }
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data("rocket: \(message)\n".utf8))
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
