import Foundation
import RocketCore
import RocketNetworking
import RocketTestServer
import Testing

@Suite struct URLSessionHTTPTransportTests {
    let transport = URLSessionHTTPTransport()

    @Test func probeReadsRangeSupportAndValidators() async throws {
        let server = try await RocketTestServer()
        let info = try await transport.probe(server.url("/file/123456?name=ubuntu.iso"))
        #expect(info.totalBytes == 123_456)
        #expect(info.acceptsRanges)
        #expect(info.etag == RocketTestServer.etag(version: "1"))
        #expect(info.lastModified != nil)
        #expect(info.suggestedFileName == "ubuntu.iso")
    }

    @Test func probeWithoutRangeSupport() async throws {
        let server = try await RocketTestServer()
        let info = try await transport.probe(server.url("/file/5000000?ranges=0"))
        #expect(info.totalBytes == 5_000_000)
        #expect(!info.acceptsRanges)
    }

    @Test func probeWithUnknownSize() async throws {
        let server = try await RocketTestServer()
        let info = try await transport.probe(server.url("/file/5000?ranges=0&length=0"))
        #expect(info.totalBytes == nil)
        #expect(!info.acceptsRanges)
    }

    @Test func probeFollowsRedirects() async throws {
        let server = try await RocketTestServer()
        let info = try await transport.probe(server.url("/redirect?to=/file/1000"))
        #expect(info.finalURL == server.url("/file/1000"))
        #expect(info.totalBytes == 1000)
    }

    @Test func fetchStreamsRequestedRange() async throws {
        let server = try await RocketTestServer()
        let response = try await transport.fetch(server.url("/file/1000000"), range: ByteRange(start: 250_000, end: 749_999), ifRange: nil)
        #expect(response.isPartial)
        #expect(response.bodyStart == 250_000)
        var data = Data()
        for try await chunk in response.body { data.append(chunk) }
        #expect(data == RocketTestServer.content(offset: 250_000, count: 500_000))
    }

    @Test func fetchWithStaleValidatorReturnsWholeFile() async throws {
        let server = try await RocketTestServer()
        let response = try await transport.fetch(
            server.url("/file/1000?version=2"), range: ByteRange(start: 500, end: nil),
            ifRange: RocketTestServer.etag(version: "1")
        )
        #expect(response.statusCode == 200)
        #expect(response.bodyStart == 0)
    }

    @Test func fetchThrowsHTTPStatus() async throws {
        let server = try await RocketTestServer()
        await #expect(throws: DownloadError.http(status: 503)) {
            _ = try await transport.fetch(server.url("/file/1000?fail=503"), range: nil, ifRange: nil)
        }
    }

    @Test func droppedConnectionThrowsNetworkError() async throws {
        let server = try await RocketTestServer()
        let response = try await transport.fetch(server.url("/file/1000000?dropAt=300000"), range: nil, ifRange: nil)
        var received = 0
        await #expect(throws: DownloadError.self) {
            for try await chunk in response.body { received += chunk.count }
        }
        // URLSession may surface the error before delivering every buffered chunk; never more than was sent.
        #expect(received <= 300_000)
    }
}
