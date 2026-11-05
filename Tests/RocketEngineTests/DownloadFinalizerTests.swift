import Darwin
import Foundation
import RocketCore
import RocketEngine
import RocketNetworking
import RocketTestServer
import Testing

@Suite struct DownloadFinalizerTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "FinalizerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let source = URL(string: "https://mirror.example.com/ubuntu.iso")!

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func partFile(bytes: Int) throws -> PartFile {
        let file = try PartFile(url: folder.appending(path: "ubuntu.iso.rocketpart"), size: nil)
        try file.write(RocketTestServer.content(count: bytes), at: 0)
        return file
    }

    func attribute(_ name: String, of url: URL) -> Data? {
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        _ = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, 0) }
        return data
    }

    @Test func renamesAndMarksAsDownloaded() throws {
        let file = try partFile(bytes: 1000)
        let final = try DownloadFinalizer.finalize(file, expectedBytes: 1000, folder: folder, fileName: "ubuntu.iso", source: source)

        #expect(final.lastPathComponent == "ubuntu.iso")
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(try Data(contentsOf: final) == RocketTestServer.content(count: 1000))

        let quarantine = try #require(attribute("com.apple.quarantine", of: final))
        #expect(String(decoding: quarantine, as: UTF8.self).hasPrefix("0081;"))
        let whereFroms = try #require(attribute("com.apple.metadata:kMDItemWhereFroms", of: final))
        let urls = try PropertyListSerialization.propertyList(from: whereFroms, format: nil) as? [String]
        #expect(urls == [source.absoluteString])
    }

    @Test func neverOverwritesExistingFiles() throws {
        try Data("mine".utf8).write(to: folder.appending(path: "ubuntu.iso"))
        try Data("mine too".utf8).write(to: folder.appending(path: "ubuntu 2.iso"))
        let final = try DownloadFinalizer.finalize(try partFile(bytes: 10), expectedBytes: 10, folder: folder, fileName: "ubuntu.iso", source: source)
        #expect(final.lastPathComponent == "ubuntu 3.iso")
        #expect(try String(contentsOf: folder.appending(path: "ubuntu.iso"), encoding: .utf8) == "mine")
    }

    @Test func rejectsWrongSize() throws {
        #expect(throws: DownloadError.sizeMismatch(expected: 2000, actual: 1000)) {
            _ = try DownloadFinalizer.finalize(try partFile(bytes: 1000), expectedBytes: 2000, folder: folder, fileName: "ubuntu.iso", source: source)
        }
    }

    @Test func sanitizesHostileNames() throws {
        let final = try DownloadFinalizer.finalize(try partFile(bytes: 10), expectedBytes: 10, folder: folder, fileName: "../../evil.sh", source: source)
        #expect(final.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(final.lastPathComponent == "evil.sh")
    }

    @Test func endToEndDownloadThenFinalize() async throws {
        let server = try await RocketTestServer()
        let transport = URLSessionHTTPTransport()
        let url = server.url("/file/3000000?name=data.bin")
        let info = try await transport.probe(url)
        let file = try PartFile(url: folder.appending(path: "data.bin.rocketpart"), size: info.totalBytes)
        let coordinator = DownloadCoordinator(url: url, info: info, file: file, connections: 4, transport: transport)
        try await coordinator.run()
        let final = try DownloadFinalizer.finalize(
            file, expectedBytes: try #require(await coordinator.totalBytes), folder: folder,
            fileName: try #require(info.suggestedFileName), source: url
        )
        #expect(final.lastPathComponent == "data.bin")
        #expect(try Data(contentsOf: final) == RocketTestServer.content(count: 3_000_000))
    }
}
