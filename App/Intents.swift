import AppIntents
import Foundation
import RocketCore
import RocketIPC

/// Shortcuts actions (FR-INT-04). They talk to the agent directly, so they work while the window is closed.
/// Shortcuts are written by the user, so Add starts without the confirmation sheet the URL scheme shows.

struct AddDownloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Download"
    static let description = IntentDescription("Starts downloading a link with Rocket, using your default folder and rules.")

    @Parameter(title: "Link") var url: URL

    static var parameterSummary: some ParameterSummary { Summary("Download \(\.$url)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { throw IntentFailure("Only http and https links are supported.") }
        guard case .download(let download) = try await IntentAgent.send(.add(url: url, directory: nil)) else {
            throw IntentFailure("Rocket could not add the download.")
        }
        return .result(value: download.id.uuidString, dialog: "Downloading \(download.fileName)")
    }
}

struct PauseAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause All Downloads"

    func perform() async throws -> some IntentResult {
        for download in try await IntentAgent.snapshot() where [.queued, .probing, .downloading].contains(download.state) {
            _ = try await IntentAgent.send(.pause(id: download.id))
        }
        return .result()
    }
}

struct ResumeAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume All Downloads"

    func perform() async throws -> some IntentResult {
        for download in try await IntentAgent.snapshot() where download.state == .paused {
            _ = try await IntentAgent.send(.resume(id: download.id))
        }
        return .result()
    }
}

struct DownloadStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Download Status"
    static let description = IntentDescription("How many downloads are running, queued, paused and failed, and how far along they are.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let downloads = try await IntentAgent.snapshot()
        let active = downloads.filter { [.probing, .downloading, .verifying].contains($0.state) }
        let count: (DownloadState) -> Int = { state in downloads.count { $0.state == state } }
        var parts = ["\(active.count) downloading", "\(count(.queued)) queued", "\(count(.paused)) paused", "\(count(.failed)) failed"]
        let total = active.compactMap(\.totalBytes).reduce(0, +)
        if total > 0 {
            parts.append("\(Int(Double(active.reduce(0) { $0 + $1.receivedBytes }) / Double(total) * 100))% done")
        }
        let summary = parts.joined(separator: ", ")
        return .result(value: summary, dialog: "\(summary)")
    }
}

struct RocketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PauseAllIntent(), phrases: ["Pause downloads in \(.applicationName)"], shortTitle: "Pause All", systemImageName: "pause")
        AppShortcut(intent: ResumeAllIntent(), phrases: ["Resume downloads in \(.applicationName)"], shortTitle: "Resume All", systemImageName: "play")
        AppShortcut(
            intent: DownloadStatusIntent(), phrases: ["\(.applicationName) download status"], shortTitle: "Status",
            systemImageName: "arrow.down.circle"
        )
    }
}

private enum IntentAgent {
    static func send(_ command: Command) async throws -> Reply {
        let reply: Reply
        do {
            reply = try await AgentClient().send(command, timeout: .seconds(15))
        } catch {
            throw IntentFailure("Rocket's background agent is not running. Open Rocket Downloader once to set it up.")
        }
        if case .error(let message) = reply { throw IntentFailure(message) }
        return reply
    }

    static func snapshot() async throws -> [Download] {
        guard case .snapshot(let downloads) = try await send(.snapshot) else { throw IntentFailure("Unexpected reply from Rocket.") }
        return downloads
    }
}

/// Error text Shortcuts shows as is.
private struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
