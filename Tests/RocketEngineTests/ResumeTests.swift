import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

actor MemoryCheckpoints {
    private(set) var segments: [Segment] = []
    func save(_ segments: [Segment]) { self.segments = segments }
}

@Suite struct ResumeTests {
    let transport = URLSessionHTTPTransport()
    let partURL = FileManager.default.temporaryDirectory.appending(path: "ResumeTests-\(UUID().uuidString).rocketpart")
    let size = 8 * Int(SegmentPlanner.mebibyte)

    func coordinator(_ url: URL, info: RemoteFileInfo, segments: [Segment] = [], store: MemoryCheckpoints) throws -> DownloadCoordinator {
        DownloadCoordinator(
            url: url, info: info, file: try PartFile(url: partURL, size: info.totalBytes), segments: segments,
            connections: 4, transport: transport, checkpointInterval: .milliseconds(50),
            onCheckpoint: { await store.save($0) }
        )
    }

    /// Starts a slow download, stops it part-way, and returns the last checkpoint.
    func interruptedDownload(_ url: URL, info: RemoteFileInfo) async throws -> [Segment] {
        let store = MemoryCheckpoints()
        let first = try coordinator(url, info: info, store: store)
        let task = Task { try await first.run() }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = await task.result
        return await store.segments
    }

    @Test func resumesFromCheckpoint() async throws {
        let server = try await RocketTestServer()
        let url = server.url("/file/\(size)?delayMs=20")
        let info = try await transport.probe(url)
        let saved = try await interruptedDownload(url, info: info)

        let progress = saved.reduce(0) { $0 + $1.received }
        #expect(progress > 0 && progress < Int64(size))
        // Every byte a checkpoint claims is really on disk.
        let partial = try Data(contentsOf: partURL)
        for segment in saved where segment.received > 0 {
            let range = Int(segment.start)..<Int(segment.next)
            #expect(partial[range] == RocketTestServer.content(offset: segment.start, count: range.count))
        }

        let store = MemoryCheckpoints()
        try await coordinator(url, info: info, segments: saved, store: store).run()
        #expect(try Data(contentsOf: partURL) == RocketTestServer.content(count: size))
        #expect(await store.segments.allSatisfy(\.isComplete))
    }

    @Test func detectsFileChangedOnServer() async throws {
        let server = try await RocketTestServer()
        let url = server.url("/file/\(size)?delayMs=20")
        let info = try await transport.probe(url)
        let saved = try await interruptedDownload(url, info: info)

        server.setVersion("2")
        await #expect(throws: DownloadError.remoteFileChanged) {
            try await coordinator(url, info: info, segments: saved, store: MemoryCheckpoints()).run()
        }
    }

    @Test func singleStreamRestartsFromZero() async throws {
        let server = try await RocketTestServer()
        let url = server.url("/file/\(size)?delayMs=20&ranges=0")
        let info = try await transport.probe(url)
        let saved = try await interruptedDownload(url, info: info)
        #expect(saved.count == 1)

        try await coordinator(url, info: info, segments: saved, store: MemoryCheckpoints()).run()
        #expect(try Data(contentsOf: partURL) == RocketTestServer.content(count: size))
    }
}
