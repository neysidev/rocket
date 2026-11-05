import Foundation
import RocketCore
import RocketIPC
@testable import RocketUI
import Testing

actor FakeAgent: AgentCommanding {
    var downloads: [Download] = []
    private(set) var sent: [Command] = []

    func set(_ downloads: [Download]) { self.downloads = downloads }

    func send(_ command: Command) -> Reply {
        sent.append(command)
        return command == .snapshot ? .snapshot(downloads) : .ok
    }
}

private func download(_ name: String, _ state: DownloadState, received: Int64 = 0, total: Int64? = 100_000_000) -> Download {
    var download = Download(url: URL(string: "https://example.com/\(name)")!, destinationPath: "/tmp", fileName: name, state: state)
    download.totalBytes = total
    download.receivedBytes = received
    return download
}

@MainActor
@Suite struct DownloadsModelTests {
    @Test func measuresSmoothedSpeedAndTimeLeft() {
        let model = DownloadsModel()
        var item = download("a.iso", .downloading, received: 0)
        let start = ContinuousClock.now
        model.apply([item], now: start)
        #expect(model.items[0].speed == 0)

        item.receivedBytes = 10_000_000
        model.apply([item], now: start + .seconds(1))
        #expect(model.items[0].speed == 10_000_000)
        #expect(model.items[0].secondsLeft == 9)

        item.receivedBytes = 30_000_000
        model.apply([item], now: start + .seconds(2))
        #expect(model.items[0].speed == 10_000_000 * 0.7 + 20_000_000 * 0.3)
    }

    @Test func filtersAndSearches() {
        let model = DownloadsModel()
        model.apply([
            download("ubuntu.iso", .downloading), download("song.mp3", .completed),
            download("broken.zip", .failed), download("later.dmg", .paused),
        ], now: .now)
        #expect(model.count(.all) == 4)
        #expect(model.count(.active) == 2)
        model.filter = .completed
        #expect(model.visibleItems.map(\.download.fileName) == ["song.mp3"])
        model.filter = .all
        model.search = "UBU"
        #expect(model.visibleItems.map(\.download.fileName) == ["ubuntu.iso"])
    }

    @Test func spaceTogglesBetweenPauseAndResume() async {
        let agent = FakeAgent()
        let running = download("a.iso", .downloading)
        let paused = download("b.iso", .paused)
        await agent.set([running, paused])
        let model = DownloadsModel(agent: agent)
        await model.refresh()

        await model.toggle([running.id])
        await model.toggle([paused.id])
        let sent = await agent.sent.filter { $0 != .snapshot }
        #expect(sent == [.pause(id: running.id), .resume(id: paused.id)])
    }

    @Test func removedDownloadsLeaveSelection() {
        let model = DownloadsModel()
        let a = download("a.iso", .completed)
        model.apply([a], now: .now)
        model.selection = [a.id]
        model.apply([], now: .now)
        #expect(model.selection.isEmpty)
    }

    @Test func metadataAndAccessibilityText() {
        var item = DownloadItem(download: download("ubuntu.iso", .downloading, received: 62_000_000), speed: 8_400_000)
        #expect(Format.detail(item) == "62 MB of 100 MB · 8.40 MB/s · 5 sec left")
        #expect(item.accessibilityLabel == "ubuntu.iso, Downloading, 62%, 8.40 MB/s, 5 sec left")
        item.download.state = .failed
        item.download.failure = .http(status: 404)
        #expect(Format.detail(item) == "The file was not found on the server (404).")
    }

    @Test func speedUnits() {
        #expect(Format.speed(512) == "512 B/s")
        #expect(Format.speed(84_300_000) == "84.3 MB/s")
        #expect(Format.speed(412_000_000) == "412 MB/s")
        #expect(Format.speed(1_250_000_000) == "1.25 GB/s")
    }

    @Test func categoriesFromExtensions() {
        #expect(FileCategory(fileName: "a.MKV") == .video)
        #expect(FileCategory(fileName: "a.tar.gz") == .archive)
        #expect(FileCategory(fileName: "README") == .other)
    }
}

@MainActor
@Suite struct NotificationTests {
    @Test func reportsOnlyNewCompletionsAndFailures() {
        let model = DownloadsModel()
        var events: [DownloadEvent] = []
        model.onEvent = { events.append($0) }

        var running = Download(url: URL(string: "https://example.com/a.iso")!, destinationPath: "/tmp", fileName: "a.iso", state: .downloading)
        let old = Download(url: URL(string: "https://example.com/old.iso")!, destinationPath: "/tmp", fileName: "old.iso", state: .completed)
        model.apply([running, old], now: .now) // first snapshot: history, no events
        #expect(events.isEmpty)

        running.state = .completed
        model.apply([running, old], now: .now)
        model.apply([running, old], now: .now) // unchanged: no repeat
        #expect(events == [.completed(running)])
    }

    @Test func notificationContent() {
        var download = Download(url: URL(string: "https://example.com/a.iso")!, destinationPath: "/tmp", fileName: "a.iso", state: .failed)
        download.failure = .diskFull
        let request = Notifier.request(for: .failed(download))
        #expect(request.content.title == "Download failed")
        #expect(request.content.subtitle == "The disk is full.")
        #expect(request.content.categoryIdentifier == "download.failed")
        #expect(request.identifier == download.id.uuidString)
    }
}
