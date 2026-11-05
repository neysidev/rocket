import Foundation
import RocketCore
import Testing

@Suite struct DownloadStatisticsTests {
    func download(_ name: String, host: String, state: DownloadState, bytes: Int64 = 1_000) -> Download {
        var download = Download(
            url: URL(string: "https://\(host)/\(name)")!,
            destinationPath: "/tmp",
            fileName: name,
            state: state
        )
        download.totalBytes = bytes
        download.receivedBytes = bytes
        return download
    }

    @Test func aggregatesCompletedAndSources() {
        let stats = DownloadStatistics.compute(from: [
            download("a.iso", host: "releases.ubuntu.com", state: .completed, bytes: 500),
            download("b.zip", host: "cdn.example.com", state: .completed, bytes: 300),
            download("c.bin", host: "cdn.example.com", state: .failed),
            download("d.pkg", host: "apple.com", state: .downloading, bytes: 9_000),
        ])
        #expect(stats.completedCount == 2)
        #expect(stats.totalCompletedBytes == 800)
        #expect(stats.failedCount == 1)
        #expect(stats.activeCount == 1)
        #expect(stats.topSources.first?.host == "releases.ubuntu.com")
        #expect(stats.bytesByCategory[.archive] == 800)
    }
}
