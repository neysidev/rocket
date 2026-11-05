import Foundation
import RocketCore
import RocketIPC
@testable import RocketUI
import Testing

/// Fixed probe results for add-sheet tests (no network).
struct TestProbeTransport: HTTPTransport, Sendable {
    func probe(_ url: URL, context: RequestContext?) async throws -> RemoteFileInfo {
        if url.host == "broken.example" { throw DownloadError.http(status: 404) }
        return RemoteFileInfo(
            finalURL: url, totalBytes: 1_000_000, acceptsRanges: true, suggestedFileName: url.lastPathComponent
        )
    }

    func fetch(_ url: URL, range: ByteRange?, ifRange: String?, context: RequestContext?) async throws -> TransferResponse {
        throw DownloadError.invalidURL
    }
}

/// Records adds sent to the agent.
actor ProbingAgent: AgentCommanding {
    private(set) var added: [Command] = []

    func send(_ command: Command) -> Reply {
        switch command {
        case let .add(url, directory, fileName, _, _, _, _, _):
            added.append(command)
            return .download(Download(url: url, destinationPath: directory ?? "/", fileName: fileName ?? "x"))
        default:
            return .ok
        }
    }
}

@MainActor
@Suite struct AddDownloadsModelTests {
    let folder = URL(filePath: "/tmp/rocket-add-tests", directoryHint: .isDirectory)

    @Test func extractsLinksFromMessyText() {
        let text = """
        Get it here: https://example.com/a.iso and http://mirror.example.org/b.zip
        ftp://old.example.com/c.tar  https://example.com/a.iso
        not a link
        """
        #expect(LinkExtractor.urls(in: text).map(\.absoluteString) == ["https://example.com/a.iso", "http://mirror.example.org/b.zip"])
    }

    @Test func readsDroppedTextFiles() throws {
        let list = FileManager.default.temporaryDirectory.appending(path: "links-\(UUID()).txt")
        try "https://example.com/1.zip\nhttps://example.com/2.zip\n".write(to: list, atomically: true, encoding: .utf8)
        let urls = LinkExtractor.urls(fromDropped: [list, URL(string: "https://example.com/3.zip")!])
        #expect(urls.map(\.lastPathComponent) == ["1.zip", "2.zip", "3.zip"])
    }

    @Test func reviewProbesEveryLinkAndReportsErrors() async {
        let model = AddDownloadsModel(
            text: "https://example.com/ubuntu.iso\nhttps://broken.example/x.zip", folder: folder,
            agent: ProbingAgent(), transport: TestProbeTransport(), existing: [], fileExists: { _ in false }
        )
        await model.review()
        #expect(model.phase == .review)
        #expect(model.candidates[0].info?.totalBytes == 1_000_000)
        #expect(model.candidates[1].error == "The file was not found on the server (404).")
        #expect(model.startCount == 1)
    }

    @Test func duplicateURLDefaultsToShowingExisting() async {
        let existing = Download(url: URL(string: "https://example.com/ubuntu.iso")!, destinationPath: folder.path, fileName: "ubuntu.iso")
        let agent = ProbingAgent()
        let model = AddDownloadsModel(
            text: existing.url.absoluteString, folder: folder, agent: agent, transport: TestProbeTransport(),
            existing: [existing], fileExists: { _ in false }
        )
        await model.review()
        #expect(model.conflict(for: model.candidates[0]) == .inList(existing.id))
        #expect(model.candidates[0].resolution == .showExisting)
        #expect(await model.start() == [existing.id])
        #expect(await agent.added.isEmpty)
    }

    @Test func existingFileIsKeptByRenaming() async {
        let taken: Set<String> = ["ubuntu.iso", "ubuntu 2.iso"]
        let agent = ProbingAgent()
        let model = AddDownloadsModel(
            text: "https://example.com/ubuntu.iso", folder: folder, agent: agent, transport: TestProbeTransport(),
            existing: [], fileExists: { taken.contains($0.lastPathComponent) }
        )
        await model.review()
        #expect(model.conflict(for: model.candidates[0]) == .fileExists)
        #expect(model.candidates[0].resolution == .keepBoth)
        _ = await model.start()
        // Folder and queue were left as opened, so the agent resolves them (rules, then defaults).
        #expect(await agent.added == [.add(url: URL(string: "https://example.com/ubuntu.iso")!, directory: nil, fileName: "ubuntu 3.iso")])
    }

    @Test func skippedLinksAreNotAdded() async {
        let agent = ProbingAgent()
        let model = AddDownloadsModel(
            text: "https://example.com/a.iso", folder: folder, agent: agent, transport: TestProbeTransport(),
            existing: [], fileExists: { _ in true }
        )
        await model.review()
        model.candidates[0].resolution = .skip
        #expect(model.startCount == 0)
        #expect(await model.start().isEmpty)
        #expect(await agent.added.isEmpty)
    }
}
