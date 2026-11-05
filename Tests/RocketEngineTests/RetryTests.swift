import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

@Suite struct RetryTests {
    let transport = URLSessionHTTPTransport()
    let partURL = FileManager.default.temporaryDirectory.appending(path: "RetryTests-\(UUID().uuidString).rocketpart")
    let size = 4 * Int(SegmentPlanner.mebibyte)
    let fastRetry = RetryPolicy(baseDelay: .milliseconds(5), maxDelay: .milliseconds(20))

    /// Probes a clean URL, then downloads from `faultyQuery` so the probe itself is not faulted.
    func download(_ server: RocketTestServer, faultyQuery: String, connections: Int = 4) async throws -> DownloadCoordinator {
        let info = try await transport.probe(server.url("/file/\(size)"))
        let coordinator = DownloadCoordinator(
            url: server.url("/file/\(size)?\(faultyQuery)"), info: info,
            file: try PartFile(url: partURL, size: info.totalBytes),
            connections: connections, transport: transport, retry: fastRetry
        )
        try await coordinator.run()
        #expect(try Data(contentsOf: partURL) == RocketTestServer.content(count: size))
        return coordinator
    }

    @Test func backoffGrowsAndIsCapped() {
        let policy = RetryPolicy()
        #expect(policy.ceiling(forAttempt: 1) == .seconds(1))
        #expect(policy.ceiling(forAttempt: 3) == .seconds(4))
        #expect(policy.ceiling(forAttempt: 10) == .seconds(60))
        for attempt in 1...8 {
            let delay = policy.delay(forAttempt: attempt)
            #expect(delay >= policy.ceiling(forAttempt: attempt) / 2 && delay <= policy.ceiling(forAttempt: attempt))
        }
    }

    @Test func recoversFromDroppedConnections() async throws {
        let server = try await RocketTestServer()
        // Drop the connection serving the middle of the file, twice.
        _ = try await download(server, faultyQuery: "dropAt=\(size / 2 + 1000)&dropCount=2")
    }

    @Test func retriesServerErrors() async throws {
        let server = try await RocketTestServer()
        let query = "fail=503&failCount=3"
        _ = try await download(server, faultyQuery: query, connections: 1)
        #expect(server.requestCount("/file/\(size)?\(query)") == 4)
    }

    @Test func rateLimitingLowersConnectionCount() async throws {
        let server = try await RocketTestServer()
        let coordinator = try await download(server, faultyQuery: "fail=429&failCount=2", connections: 4)
        #expect(await coordinator.connectionLimit == 2)
    }

    @Test func fatalErrorsAreNotRetried() async throws {
        let server = try await RocketTestServer()
        let query = "fail=404&failCount=100"
        await #expect(throws: DownloadError.http(status: 404)) {
            _ = try await download(server, faultyQuery: query, connections: 1)
        }
        #expect(server.requestCount("/file/\(size)?\(query)") == 1)
    }

    @Test func givesUpAfterMaxAttempts() async throws {
        let server = try await RocketTestServer()
        let query = "fail=500&failCount=100"
        await #expect(throws: DownloadError.http(status: 500)) {
            _ = try await download(server, faultyQuery: query, connections: 1)
        }
        #expect(server.requestCount("/file/\(size)?\(query)") == fastRetry.maxAttempts)
    }

    @Test func reachabilityReportsCurrentState() async {
        var updates = NetworkReachability.updates().makeAsyncIterator()
        #expect(await updates.next() != nil)
    }
}
