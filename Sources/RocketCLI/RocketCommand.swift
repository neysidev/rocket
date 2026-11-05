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
        subcommands: [Add.self, Info.self, List.self, Limit.self, QueueCommand.self, Refresh.self, Pause.self, Resume.self, Cancel.self]
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
    @Option(help: "Queue name (default: Default).") var queue: String?
    @Option(name: .customLong("header"), help: "Extra request header, \"Name: value\" (repeatable).") var headers: [String] = []
    @Option(help: "Referer header.") var referer: String?
    @Option(name: .customLong("user-agent"), help: "User-Agent header.") var userAgent: String?
    @Option(help: "Cookie header value (stored in the Keychain).") var cookie: String?
    @Option(help: "HTTP Basic credentials, user:password (password stored in the Keychain).") var user: String?
    @Flag(help: "Wait until the download finishes; exit 1 if it fails.") var wait = false
    @Flag(help: "Print JSON.") var json = false

    func validate() throws {
        guard URL(string: url)?.scheme != nil else { throw ValidationError("Not a URL: \(url)") }
        if let connections, !(1...16).contains(connections) { throw ValidationError("--connections must be 1–16") }
        if let limit, ByteRate.parse(limit) == nil { throw ValidationError("Not a speed: \(limit). Try 2M or 500K.") }
    }

    func run() async throws {
        let directory = dir.map { URL(filePath: $0, relativeTo: .currentDirectory()).path }
        var queueID: String?
        if let queue { queueID = try await Agent.queue(named: queue).id }
        let credentials = user.map { $0.split(separator: ":", maxSplits: 1).map(String.init) }
        let context = RequestContext(
            headers: RequestContext.headers(fromLines: headers), referrer: referer, userAgent: userAgent, cookies: cookie,
            username: credentials?.first, password: credentials.flatMap { $0.count > 1 ? $0[1] : nil }
        )
        let reply = try await Agent.send(.add(
            url: URL(string: url)!, directory: directory, fileName: name, connections: connections,
            speedLimit: limit.flatMap(ByteRate.parse), queueID: queueID, context: context
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

struct QueueCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "queue", abstract: "List, add or remove queues.", subcommands: [QueueList.self, QueueAdd.self, QueueRemove.self],
        defaultSubcommand: QueueList.self
    )
}

struct QueueList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List queues.")
    @Flag(help: "Print JSON.") var json = false

    func run() async throws {
        let queues = try await Agent.queues()
        if json { return Output.printJSON(queues) }
        for queue in queues {
            var line = "\(queue.name)  max \(queue.maxActive)"
            if let schedule = queue.schedule { line += "  \(schedule.summary)" }
            if let limit = queue.speedLimit { line += "  limit \(Output.bytes(limit))/s" }
            if queue.postAction != .none { line += "  then \(queue.postAction.rawValue)" }
            print(line)
        }
    }
}

struct QueueAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a queue, or update one with the same name.")
    @Argument var name: String
    @Option(help: "Simultaneous downloads, 1–16.") var max = 3
    @Option(help: "Window start, HH:MM.") var start: String?
    @Option(help: "Window end, HH:MM (may be earlier than start for overnight).") var stop: String?
    @Option(help: "Days, e.g. mon,tue,fri or weekdays, weekends, all.") var days = "all"
    @Option(help: "Speed limit for the queue, e.g. 2M.") var limit: String?
    @Option(help: "After the queue finishes: none, notify, sleep, shutDown, quitRocket, runShortcut.") var then = PostQueueAction.none.rawValue
    @Option(help: "Shortcut name for --then runShortcut.") var shortcut: String?

    func validate() throws {
        if (start == nil) != (stop == nil) { throw ValidationError("Use --start and --stop together.") }
        if let start, Self.minutes(start) == nil { throw ValidationError("Not a time: \(start). Use HH:MM.") }
        if let stop, Self.minutes(stop) == nil { throw ValidationError("Not a time: \(stop). Use HH:MM.") }
        if Self.weekdays(days) == nil { throw ValidationError("Not days: \(days).") }
        if PostQueueAction(rawValue: then) == nil { throw ValidationError("Unknown action: \(then).") }
        if let limit, ByteRate.parse(limit) == nil { throw ValidationError("Not a speed: \(limit).") }
    }

    func run() async throws {
        let existing = try await Agent.queues()
        var queue = existing.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? DownloadQueue(name: name, sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1)
        queue.maxActive = max
        queue.schedule = start.flatMap(Self.minutes).flatMap { from in
            stop.flatMap(Self.minutes).map { QueueSchedule(start: from, stop: $0, weekdays: Self.weekdays(days) ?? Set(1...7)) }
        }
        queue.speedLimit = limit.flatMap(ByteRate.parse)
        queue.postAction = PostQueueAction(rawValue: then) ?? .none
        queue.shortcutName = shortcut
        try await Agent.expectOK(.saveQueue(queue))
    }

    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func weekdays(_ text: String) -> Set<Int>? {
        switch text.lowercased() {
        case "all", "daily": return Set(1...7)
        case "weekdays": return Set(2...6)
        case "weekends": return [1, 7]
        default:
            let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            let days = text.lowercased().split(separator: ",").map { names.firstIndex(of: String($0.prefix(3))).map { $0 + 1 } }
            return days.contains(nil) || days.isEmpty ? nil : Set(days.compactMap { $0 })
        }
    }
}

struct QueueRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a queue; its downloads move to Default.")
    @Argument var name: String
    func run() async throws { try await Agent.expectOK(.deleteQueue(id: Agent.queue(named: name).id)) }
}

struct Refresh: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Replace an expired link with a fresh one, keeping progress.")
    @Argument(help: "Download ID or a unique prefix of it.") var id: String
    @Argument(help: "The new link to the same file.") var url: String

    func run() async throws {
        guard let url = URL(string: url) else { throw ValidationError("Not a URL: \(self.url)") }
        guard case .download(let download) = try await Agent.send(.refreshURL(id: Agent.resolve(id), url: url)) else { throw ExitCode.failure }
        Output.print(download, json: false)
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

    static func queues() async throws -> [DownloadQueue] {
        let reply = try await send(.queues)
        guard case .queues(let queues) = reply else { throw unexpected(reply) }
        return queues
    }

    static func queue(named name: String) async throws -> DownloadQueue {
        guard let queue = try await queues().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.id == name }) else {
            throw ValidationError("No queue named \(name). See rocket queue list.")
        }
        return queue
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
