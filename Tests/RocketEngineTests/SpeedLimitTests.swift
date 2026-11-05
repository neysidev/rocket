import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

@Suite struct SpeedLimitTests {
    let transport = URLSessionHTTPTransport()
    let size = 4_000_000

    func timedDownload(_ server: RocketTestServer, limiters: [BandwidthLimiter]) async throws -> Duration {
        let url = server.url("/file/\(size)")
        let info = try await transport.probe(url)
        let part = FileManager.default.temporaryDirectory.appending(path: "Limit-\(UUID()).rocketpart")
        let coordinator = DownloadCoordinator(
            url: url, info: info, file: try PartFile(url: part, size: info.totalBytes),
            connections: 4, transport: transport, limiters: limiters
        )
        let elapsed = try await ContinuousClock().measure { try await coordinator.run() }
        #expect(try Data(contentsOf: part) == RocketTestServer.content(count: size))
        return elapsed
    }

    @Test func limitThrottlesAcrossAllConnections() async throws {
        let server = try await RocketTestServer()
        // 4 MB at 4 MB/s with a 0.25 s burst: at least ~0.75 s across the 4 connections together.
        let elapsed = try await timedDownload(server, limiters: [BandwidthLimiter(bytesPerSecond: 4_000_000)])
        #expect(elapsed >= .milliseconds(700))
        #expect(elapsed < .seconds(3))
    }

    @Test func unlimitedIsFast() async throws {
        let server = try await RocketTestServer()
        #expect(try await timedDownload(server, limiters: [BandwidthLimiter()]) < .milliseconds(500))
    }

    @Test func tightestOfSeveralLimitersWins() async throws {
        let server = try await RocketTestServer()
        let elapsed = try await timedDownload(server, limiters: [
            BandwidthLimiter(bytesPerSecond: 100_000_000), BandwidthLimiter(bytesPerSecond: 4_000_000),
        ])
        #expect(elapsed >= .milliseconds(700))
    }

    @Test func parsesRates() {
        #expect(ByteRate.parse("2M") == 2_000_000)
        #expect(ByteRate.parse("2 MB/s") == 2_000_000)
        #expect(ByteRate.parse("500k") == 500_000)
        #expect(ByteRate.parse("1.5G") == 1_500_000_000)
        #expect(ByteRate.parse("1048576") == 1_048_576)
        #expect(ByteRate.parse("fast") == nil)
        #expect(ByteRate.parse("0") == nil)
    }
}

@Suite struct BackpressureTests {
    final class Calls: @unchecked Sendable {
        var pauses = 0, resumes = 0
    }

    @Test func pausesWhenFullAndResumesWhenDrained() async throws {
        let calls = Calls()
        let body = HTTPBody(highWater: 300, lowWater: 100)
        body.setControl(.init(pause: { calls.pauses += 1 }, resume: { calls.resumes += 1 }, cancel: {}))
        for _ in 0..<4 { body.yield(Data(count: 100)) } // 400 > 300
        #expect(calls.pauses == 1)

        var iterator = body.makeAsyncIterator()
        _ = try await iterator.next() // 300 left
        _ = try await iterator.next() // 200 left
        #expect(calls.resumes == 0)
        _ = try await iterator.next() // 100 left, still not below low water
        _ = try await iterator.next() // 0 left
        #expect(calls.resumes == 1)
        body.finish(throwing: nil)
        #expect(try await iterator.next() == nil)
    }
}
