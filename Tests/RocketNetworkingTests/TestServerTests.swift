import Foundation
import RocketTestServer
import Testing

@Suite struct TestServerTests {
    let session = URLSession(configuration: .ephemeral)

    @Test func servesFullFile() async throws {
        let server = try await RocketTestServer()
        let (data, response) = try await session.data(from: server.url("/file/200000"))
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(data == RocketTestServer.content(count: 200_000))
    }

    @Test func servesRange() async throws {
        let server = try await RocketTestServer()
        var request = URLRequest(url: server.url("/file/200000"))
        request.setValue("bytes=1000-1999", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 206)
        #expect(http.value(forHTTPHeaderField: "Content-Range") == "bytes 1000-1999/200000")
        #expect(data == RocketTestServer.content(offset: 1000, count: 1000))
    }

    @Test func ifRangeMismatchSendsWholeFile() async throws {
        let server = try await RocketTestServer()
        var request = URLRequest(url: server.url("/file/5000?version=2"))
        request.setValue("bytes=100-", forHTTPHeaderField: "Range")
        request.setValue(RocketTestServer.etag(version: "1"), forHTTPHeaderField: "If-Range")
        let (data, response) = try await session.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == RocketTestServer.content(count: 5000, version: "2"))
    }

    @Test func failsConfiguredNumberOfTimes() async throws {
        let server = try await RocketTestServer()
        let url = server.url("/file/10?fail=503&failCount=2")
        var statuses: [Int] = []
        for _ in 0..<3 {
            let (_, response) = try await session.data(from: url)
            statuses.append((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        #expect(statuses == [503, 503, 200])
    }

    @Test func dropsConnectionMidBody() async throws {
        let server = try await RocketTestServer()
        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: server.url("/file/1000000?dropAt=300000"))
        }
    }
}
