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
        let sent = await agent.sent.filter { $0 != .snapshot && $0 != .queues }
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

@MainActor
@Suite struct PanelStatsTests {
    func item(_ state: DownloadState, completedHoursAgo: Double? = nil, bytes: Int64 = 1_000) -> Download {
        var download = Download(url: URL(string: "https://example.com/f")!, destinationPath: "/tmp", fileName: "f", state: state)
        download.totalBytes = bytes
        download.completedAt = completedHoursAgo.map { Date.now.addingTimeInterval(-$0 * 3600) }
        return download
    }

    @Test func countsAndHourlyThroughput() {
        let model = DownloadsModel()
        model.apply([
            item(.downloading), item(.queued), item(.queued), item(.paused),
            item(.completed, completedHoursAgo: 0.2, bytes: 500), item(.completed, completedHoursAgo: 0.5, bytes: 250),
            item(.completed, completedHoursAgo: 5.5, bytes: 100), item(.completed, completedHoursAgo: 30, bytes: 9_999),
        ], now: .now)
        #expect(model.transferringCount == 1)
        #expect(model.queuedCount == 2)
        let buckets = model.hourlyThroughput()
        #expect(buckets.count == 24)
        #expect(buckets[23] == 750)
        #expect(buckets[18] == 100)
        #expect(buckets.reduce(0, +) == 850) // older than 24 h is excluded
    }

    @Test func sparklineKeepsLast16Samples() {
        let model = DownloadsModel()
        for _ in 0..<20 { model.apply([], now: .now) }
        #expect(model.speedHistory.count == 16)
    }
}

@MainActor
@Suite struct QueueUITests {
    func download(_ name: String, queue: String, state: DownloadState, position: Double) -> Download {
        var download = Download(url: URL(string: "https://example.com/\(name)")!, destinationPath: "/tmp", fileName: name, state: state)
        download.queueID = queue
        download.position = position
        return download
    }

    @Test func queueFilterShowsRunOrder() {
        let model = DownloadsModel()
        model.apply([
            download("b", queue: "night", state: .queued, position: 2), download("a", queue: "night", state: .queued, position: 1),
            download("x", queue: "default", state: .queued, position: 0),
        ], now: .now)
        model.filter = .queue("night")
        #expect(model.visibleItems.map(\.download.fileName) == ["a", "b"])
        #expect(model.count(.queue("night")) == 2)
    }

    @Test func dragReorderSendsMoveBeforeTheRightNeighbour() async {
        let agent = FakeAgent()
        let items = [
            download("a", queue: "night", state: .queued, position: 1), download("b", queue: "night", state: .queued, position: 2),
            download("c", queue: "night", state: .queued, position: 3),
        ]
        await agent.set(items)
        let model = DownloadsModel(agent: agent)
        await model.refresh()
        model.filter = .queue("night")
        await model.moveInCurrentQueue(from: [2], to: 0) // c to the top
        let moves = await agent.sent.filter { if case .move = $0 { true } else { false } }
        #expect(moves == [.move(ids: [items[2].id], toQueue: "night", before: items[0].id)])
    }
}

@MainActor
@Suite struct PolishTests {
    func download(_ name: String, _ state: DownloadState, received: Int64 = 0, total: Int64? = nil) -> Download {
        var download = Download(url: URL(string: "https://example.com/\(name)")!, destinationPath: "/tmp", fileName: name, state: state)
        download.receivedBytes = received
        download.totalBytes = total
        return download
    }

    @Test func overallProgressCountsOnlyRunningWithKnownSize() {
        let model = DownloadsModel()
        model.apply([
            download("a", .downloading, received: 25, total: 100), download("b", .queued, received: 0, total: 100),
            download("c", .downloading, received: 5, total: nil), download("d", .completed, received: 50, total: 50),
        ], now: .now)
        #expect(model.overallFraction == 0.125)
        model.apply([download("d", .completed, received: 50, total: 50)], now: .now)
        #expect(model.overallFraction == nil)
    }

    @Test func clearCompletedRemovesFinishedOnly() async {
        let agent = FakeAgent()
        let done = download("done", .completed), gone = download("gone", .cancelled), running = download("run", .downloading)
        await agent.set([done, gone, running])
        let model = DownloadsModel(agent: agent)
        await model.refresh()
        await model.clearCompleted()
        let removed = await agent.sent.compactMap { if case let .remove(id, deleteFile) = $0 { (id, deleteFile) } else { nil } }
        #expect(Set(removed.map(\.0)) == [done.id, gone.id])
        #expect(removed.allSatisfy { !$0.1 }) // files stay
    }

    @Test func sortsHistory() {
        let model = DownloadsModel()
        model.apply([
            download("b.iso", .completed, total: 10), download("A.zip", .failed, total: 300), download("c.mov", .downloading, total: 20),
        ], now: .now)
        model.sort = .name
        #expect(model.visibleItems.map(\.download.fileName) == ["A.zip", "b.iso", "c.mov"])
        model.sort = .size
        #expect(model.visibleItems.map(\.download.fileName) == ["A.zip", "c.mov", "b.iso"])
        model.sort = .status
        #expect(model.visibleItems.map(\.download.fileName) == ["c.mov", "A.zip", "b.iso"])
    }
}

@MainActor
@Suite struct RefinementTests {
    @Test func queuedHasItsOwnFilterAndActiveExcludesIt() {
        let model = DownloadsModel()
        model.apply([download("a", .queued), download("b", .downloading), download("c", .paused)], now: .now)
        #expect(model.count(.queued) == 1)
        #expect(model.count(.active) == 2)
        model.filter = .queued
        #expect(model.visibleItems.map(\.download.fileName) == ["a"])
    }

    @Test func categorySizeAndDateCombineWithSearch() {
        let model = DownloadsModel()
        var old = download("old.mp4", .completed, total: 2_000_000_000)
        old.createdAt = .now.addingTimeInterval(-40 * 86400)
        model.apply([
            download("clip.mp4", .completed, total: 2_000_000_000), download("small.mp4", .completed, total: 5_000_000),
            download("notes.pdf", .completed, total: 2_000_000_000), old,
        ], now: .now)
        model.category = .video
        #expect(model.visibleItems.count == 3)
        model.sizeFilter = .huge
        #expect(Set(model.visibleItems.map(\.download.fileName)) == ["clip.mp4", "old.mp4"])
        model.dateFilter = .month
        #expect(model.visibleItems.map(\.download.fileName) == ["clip.mp4"])
        model.search = "nothing"
        #expect(model.visibleItems.isEmpty)
        #expect(model.hasRefinements)
        model.clearRefinements()
        model.search = ""
        #expect(model.visibleItems.count == 4)
        #expect(!model.hasRefinements)
    }

    @Test func oldestAndProgressSorts() {
        let model = DownloadsModel()
        // The agent sends newest first.
        model.apply([download("new", .downloading, received: 10, total: 100), download("mid", .paused, received: 90, total: 100),
                     download("old", .completed, received: 100, total: 100)], now: .now)
        model.sort = .newest
        #expect(model.visibleItems.map(\.download.fileName) == ["new", "mid", "old"])
        model.sort = .oldest
        #expect(model.visibleItems.map(\.download.fileName) == ["old", "mid", "new"])
        model.sort = .progress
        #expect(model.visibleItems.map(\.download.fileName) == ["old", "mid", "new"])
    }

    @Test func queuePositionsCountWaitingDownloadsPerQueue() {
        let model = DownloadsModel()
        func make(_ name: String, _ queue: String, _ state: DownloadState, _ position: Double) -> Download {
            var d = download(name, state)
            d.queueID = queue
            d.position = position
            return d
        }
        let items = [make("b", "night", .queued, 2), make("a", "night", .queued, 1), make("run", "night", .downloading, 0),
                     make("x", "default", .queued, 5)]
        model.apply(items, now: .now)
        let positions = model.queuePositions
        #expect(positions[items[1].id] == 1)
        #expect(positions[items[0].id] == 2)
        #expect(positions[items[3].id] == 1)
        #expect(positions[items[2].id] == nil)
    }

    @Test func categoriesFromSystemTypesAndMIME() {
        #expect(FileCategory(fileName: "song.wma") == .music) // not in the table; UTType knows it
        #expect(FileCategory(fileName: "index.html") == .document)
        #expect(FileCategory(fileName: "download", mimeType: "video/mp4") == .video)
        #expect(FileCategory(fileName: "download", mimeType: "application/zip; charset=binary") == .archive)
        #expect(FileCategory(fileName: "download", mimeType: "application/octet-stream") == .other)
    }
}
