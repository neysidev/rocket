import RocketCore
@testable import RocketUI
import Testing

@MainActor
@Suite struct CommandPaletteTests {
    @Test func findsDownloadsByExtensionAndStatus() {
        let model = DownloadsModel()
        model.apply([
            Download(url: URL(string: "https://example.com/a.iso")!, destinationPath: "/tmp", fileName: "ubuntu.iso", state: .downloading),
            Download(url: URL(string: "https://example.com/b.mp3")!, destinationPath: "/tmp", fileName: "song.mp3", state: .completed),
        ], now: .now)

        let iso = CommandRegistry.build(model: model, query: "iso").map(\.id)
        #expect(iso.contains(where: { $0.hasPrefix("download:") }))

        let failedSearch = CommandRegistry.build(model: model, query: "completed").map(\.title)
        #expect(failedSearch.contains("song.mp3"))
    }

    @Test func includesContextualSelectionCommands() {
        let model = DownloadsModel()
        let item = Download(url: URL(string: "https://example.com/x.zip")!, destinationPath: "/tmp", fileName: "x.zip", state: .paused)
        model.apply([item], now: .now)
        model.selection = [item.id]

        let ids = Set(CommandRegistry.build(model: model, query: "").map(\.id))
        #expect(ids.contains("sel:resume"))
        #expect(ids.contains("sel:finder"))
    }
}
