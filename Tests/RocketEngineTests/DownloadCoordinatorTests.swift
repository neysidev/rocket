import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

@Suite struct DownloadCoordinatorTests {
    let transport = URLSessionHTTPTransport()
    let directory = FileManager.default.temporaryDirectory.appending(path: "RocketEngineTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func download(_ url: URL, connections: Int = 8) async throws -> (data: Data, coordinator: DownloadCoordinator) {
        let info = try await transport.probe(url)
        let partURL = directory.appending(path: "file.rocketpart")
        let coordinator = DownloadCoordinator(
            url: url, info: info, file: try PartFile(url: partURL, size: info.totalBytes),
            connections: connections, transport: transport
        )
        try await coordinator.run()
        return (try Data(contentsOf: partURL), coordinator)
    }

    @Test func segmentedDownloadMatchesServerBytes() async throws {
        let server = try await RocketTestServer()
        let size = 20 * Int(SegmentPlanner.mebibyte) + 12_345
        let (data, coordinator) = try await download(server.url("/file/\(size)"))
        #expect(coordinator.isSegmented)
        #expect(await coordinator.segments.count >= 8)
        #expect(await coordinator.receivedBytes == Int64(size))
        #expect(data == RocketTestServer.content(count: size))
        #expect(server.requestCount("/file/\(size)") >= 9) // probe + one request per segment
    }

    @Test func slowWorkersAreRebalanced() async throws {
        let server = try await RocketTestServer()
        let size = 12 * Int(SegmentPlanner.mebibyte)
        let (data, coordinator) = try await download(server.url("/file/\(size)?delayMs=20&delayFrom=\(size * 3 / 4)"), connections: 4)
        #expect(await coordinator.segments.count > 4)
        #expect(data == RocketTestServer.content(count: size))
    }

    @Test func fallsBackToSingleStreamWithoutRanges() async throws {
        let server = try await RocketTestServer()
        let (data, coordinator) = try await download(server.url("/file/3000000?ranges=0"))
        #expect(!coordinator.isSegmented)
        #expect(await coordinator.segments.count == 1)
        #expect(data == RocketTestServer.content(count: 3_000_000))
    }

    @Test func downloadsFileOfUnknownSize() async throws {
        let server = try await RocketTestServer()
        let (data, coordinator) = try await download(server.url("/file/2500000?ranges=0&length=0"))
        #expect(await coordinator.totalBytes == 2_500_000)
        #expect(data == RocketTestServer.content(count: 2_500_000))
    }

    @Test func smallFileUsesOneConnection() async throws {
        let server = try await RocketTestServer()
        let (data, coordinator) = try await download(server.url("/file/100000"))
        #expect(await coordinator.segments.count == 1)
        #expect(data == RocketTestServer.content(count: 100_000))
    }
}
