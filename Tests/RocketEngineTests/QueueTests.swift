import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

actor Recorder {
    private(set) var actions: [String] = []
    private(set) var activity: [Bool] = []
    func action(_ name: String) { actions.append(name) }
    func active(_ value: Bool) { activity.append(value) }
}

@Suite struct QueueTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "QueueTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let repository = MemoryRepository()
    let recorder = Recorder()
    let clock = TestClock(Self.date(weekday: 4, hour: 12)) // Wednesday noon
    let scheduler: DownloadScheduler

    init() {
        let (recorder, clock) = (recorder, clock)
        scheduler = DownloadScheduler(
            repository: repository, checkpoints: repository, queues: repository, transport: URLSessionHTTPTransport(),
            retry: RetryPolicy(baseDelay: .milliseconds(5), maxDelay: .milliseconds(20)), checkpointInterval: .milliseconds(50),
            defaults: RocketDefaults(store: UserDefaults(suiteName: "QueueTests-\(UUID().uuidString)")!),
            now: { clock.now },
            runPostAction: { await recorder.action("\($0.name):\($0.postAction.rawValue)") },
            onActivityChange: { await recorder.active($0) }
        )
    }

    static func date(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        // 2026-11-01 is a Sunday (weekday 1).
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: weekday, hour: hour, minute: minute))!
    }

    func states(_ ids: [UUID]) async throws -> [DownloadState] {
        let all = try await scheduler.snapshot()
        return ids.map { id in all.first { $0.id == id }!.state }
    }

    func waitUntil(timeout: Duration = .seconds(20), _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out")
    }

    // MARK: Schedule math

    @Test func dayWindow() {
        let window = QueueSchedule(start: 9 * 60, stop: 18 * 60, weekdays: Set(2...6))
        #expect(window.isOpen(at: Self.date(weekday: 4, hour: 12)))
        #expect(!window.isOpen(at: Self.date(weekday: 4, hour: 18)))
        #expect(!window.isOpen(at: Self.date(weekday: 1, hour: 12))) // Sunday
    }

    @Test func overnightWindowBelongsToItsStartDay() {
        let night = QueueSchedule(start: 23 * 60, stop: 6 * 60, weekdays: [6]) // Friday night
        #expect(night.isOpen(at: Self.date(weekday: 6, hour: 23, minute: 30)))
        #expect(night.isOpen(at: Self.date(weekday: 7, hour: 5)))  // Saturday early morning
        #expect(!night.isOpen(at: Self.date(weekday: 7, hour: 23, minute: 30)))
        #expect(!night.isOpen(at: Self.date(weekday: 6, hour: 5))) // Friday early morning belongs to Thursday
        #expect(night.summary.hasPrefix("23:00–06:00"))
    }

    // MARK: Scheduler

    @Test func queueLimitRunsOneAtATimeInOrder() async throws {
        let server = try await RocketTestServer()
        try await scheduler.saveQueue(DownloadQueue(id: "serial", name: "Serial", maxActive: 1))
        var ids: [UUID] = []
        for index in 0..<3 {
            ids.append(try await scheduler.add(url: server.url("/file/3000000?delayMs=20&name=\(index).bin"), folder: folder, queueID: "serial").id)
        }
        // The first is already running; move the last ahead of the second.
        try await scheduler.move(ids: [ids[2]], toQueue: "serial", before: ids[1])
        try await waitUntil { try await states(ids)[2] == .completed }
        #expect(try await states(ids)[1] != .completed)

        var maxRunning = 0
        try await waitUntil {
            let current = try await states(ids)
            maxRunning = max(maxRunning, current.count { [.probing, .downloading, .verifying].contains($0) })
            return current.allSatisfy { $0 == .completed }
        }
        #expect(maxRunning == 1)
    }

    @Test func scheduledQueueWaitsForItsWindowAndParksWhenItCloses() async throws {
        let server = try await RocketTestServer()
        let night = DownloadQueue(id: "night", name: "Night", schedule: QueueSchedule(start: 60, stop: 7 * 60), postAction: .sleep)
        try await scheduler.saveQueue(night)
        let id = try await scheduler.add(url: server.url("/file/8000000?delayMs=40&name=big.bin"), folder: folder, queueID: "night").id

        try await Task.sleep(for: .milliseconds(200))
        #expect(try await states([id]) == [.queued]) // noon: closed

        clock.set(Self.date(weekday: 5, hour: 1, minute: 30))
        try await scheduler.tick()
        try await waitUntil { try await states([id]) == [.downloading] }
        try await Task.sleep(for: .milliseconds(300))

        clock.set(Self.date(weekday: 5, hour: 7, minute: 1))
        try await scheduler.tick()
        #expect(try await states([id]) == [.queued]) // parked, progress kept
        let parked = try await scheduler.snapshot().first { $0.id == id }!
        #expect(parked.receivedBytes > 0)
        #expect(await recorder.actions.isEmpty) // not finished, just closed

        clock.set(Self.date(weekday: 6, hour: 2))
        try await scheduler.tick()
        try await waitUntil { try await states([id]) == [.completed] }
        try await waitUntil { await recorder.actions == ["Night:sleep"] }
        #expect(await recorder.activity == [true, false, true, false])
    }

    @Test func queueSpeedLimitApplies() async throws {
        let server = try await RocketTestServer()
        try await scheduler.saveQueue(DownloadQueue(id: "slow", name: "Slow", speedLimit: 2_000_000))
        let start = ContinuousClock.now
        let id = try await scheduler.add(url: server.url("/file/3000000?name=s.bin"), folder: folder, queueID: "slow").id
        try await waitUntil { try await states([id]) == [.completed] }
        #expect(ContinuousClock.now - start >= .milliseconds(1000))
    }

    @Test func deletingAQueueMovesItsDownloadsToDefault() async throws {
        let server = try await RocketTestServer()
        try await scheduler.saveQueue(DownloadQueue(id: "temp", name: "Temp", schedule: QueueSchedule(start: 0, stop: 1, weekdays: [])))
        let id = try await scheduler.add(url: server.url("/file/1000?name=t.bin"), folder: folder, queueID: "temp").id
        try await scheduler.deleteQueue(id: "temp")
        try await waitUntil { try await states([id]) == [.completed] }
        #expect(try await scheduler.snapshot().first { $0.id == id }?.queueID == DownloadQueue.defaultID)
        #expect(try await scheduler.queues().map(\.id) == [DownloadQueue.defaultID])
    }
}
