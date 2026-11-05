import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

@Suite struct RuleTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "RuleTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func matching() {
        let url = URL(string: "https://cdn.releases.example.com/ubuntu.iso")!
        #expect(RuleMatch(domains: ["example.com"]).matches(url: url, fileName: "ubuntu.iso", size: nil))
        #expect(!RuleMatch(domains: ["ample.com"]).matches(url: url, fileName: "ubuntu.iso", size: nil))
        #expect(RuleMatch(extensions: [".ISO", "dmg"]).matches(url: url, fileName: "ubuntu.iso", size: nil))
        #expect(!RuleMatch(extensions: ["zip"]).matches(url: url, fileName: "ubuntu.iso", size: nil))
        #expect(RuleMatch(minBytes: 1_000).matches(url: url, fileName: "x", size: 5_000))
        #expect(!RuleMatch(minBytes: 1_000).matches(url: url, fileName: "x", size: nil)) // unknown size never matches
        #expect(!RuleMatch(maxBytes: 1_000).matches(url: url, fileName: "x", size: 5_000))
        #expect(RuleMatch().matches(url: url, fileName: "x", size: nil))
    }

    @Test func firstEnabledByPriorityWins() {
        let url = URL(string: "https://example.com/a.iso")!
        let rules = [
            DownloadRule(id: "b", name: "b", priority: 2, match: RuleMatch(extensions: ["iso"])),
            DownloadRule(id: "off", name: "off", enabled: false, priority: 0, match: RuleMatch(extensions: ["iso"])),
            DownloadRule(id: "a", name: "a", priority: 1, match: RuleMatch(domains: ["example.com"])),
        ]
        #expect(DownloadRule.first(in: rules, url: url, fileName: "a.iso", size: nil)?.id == "a")
    }

    func scheduler(_ repository: MemoryRepository, autoSort: Bool) -> DownloadScheduler {
        let defaults = RocketDefaults(store: UserDefaults(suiteName: "RuleTests-\(UUID().uuidString)")!)
        defaults.folder = base
        defaults.connections = 6
        defaults.autoSort = autoSort
        return DownloadScheduler(
            repository: repository, checkpoints: repository, queues: repository, rules: repository,
            transport: URLSessionHTTPTransport(), defaults: defaults
        )
    }

    @Test func requestBeatsRuleBeatsDefaults() async throws {
        let server = try await RocketTestServer()
        let repository = MemoryRepository()
        await repository.save(DownloadQueue(id: "night", name: "Night", schedule: QueueSchedule(start: 0, stop: 1, weekdays: [])))
        await repository.save(DownloadRule(name: "ISOs", match: RuleMatch(extensions: ["iso"]), action: RuleAction(
            folderPath: base.appending(path: "Linux").path, queueID: "night", connections: 2, speedLimit: 1_000_000
        )))
        let scheduler = scheduler(repository, autoSort: true)

        let ruled = try await scheduler.add(url: server.url("/file/1000?name=ubuntu.iso"))
        #expect(ruled.destinationPath == base.appending(path: "Linux").path)
        #expect(ruled.queueID == "night")
        #expect(ruled.connections == 2)
        #expect(ruled.speedLimit == 1_000_000)

        let explicit = try await scheduler.add(url: server.url("/file/1000?name=debian.iso"), folder: base.appending(path: "Mine"), connections: 4)
        #expect(explicit.destinationPath == base.appending(path: "Mine").path)
        #expect(explicit.connections == 4)
        #expect(explicit.queueID == "night") // not overridden by the request, so the rule still applies

        let plain = try await scheduler.add(url: server.url("/file/1000?name=movie.mkv"))
        #expect(plain.destinationPath == base.appending(path: "Video").path) // auto-sort under the default folder
        #expect(plain.connections == 6)
        #expect(plain.queueID == DownloadQueue.defaultID)
    }

    @Test func autoSortOffKeepsDefaultFolder() async throws {
        let server = try await RocketTestServer()
        let download = try await scheduler(MemoryRepository(), autoSort: false).add(url: server.url("/file/1000?name=movie.mkv"))
        #expect(download.destinationPath == base.path)
    }
}

@Suite struct DetailsTests {
    @Test func logsRetriesAndReportsSegments() async throws {
        let server = try await RocketTestServer()
        let repository = MemoryRepository()
        let scheduler = DownloadScheduler(
            repository: repository, checkpoints: repository, queues: repository, transport: URLSessionHTTPTransport(),
            retry: RetryPolicy(baseDelay: .milliseconds(5), maxDelay: .milliseconds(20)),
            defaults: RocketDefaults(store: UserDefaults(suiteName: "Details-\(UUID().uuidString)")!)
        )
        let folder = FileManager.default.temporaryDirectory.appending(path: "Details-\(UUID())", directoryHint: .isDirectory)
        // Probe gets one 503 too, so add a clean URL's info via a manual record instead.
        let url = server.url("/file/6000000?fail=503&failCount=3&delayMs=5")
        var download = Download(url: url, destinationPath: folder.path, fileName: "d.bin", connections: 4)
        download.remoteInfo = try await URLSessionHTTPTransport().probe(server.url("/file/6000000"))
        download.finalURL = url
        await repository.save(download)
        try await scheduler.start()

        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline, try await scheduler.snapshot().first?.state != .completed {
            try await Task.sleep(for: .milliseconds(20))
        }
        let details = try await scheduler.details(id: download.id)
        let messages = details.log.map(\.message)
        #expect(messages.contains { $0.hasPrefix("Downloading with up to 4 connections") })
        #expect(messages.contains { $0.contains("Server is busy") })
        #expect(messages.last?.hasPrefix("Completed") == true)
    }
}
