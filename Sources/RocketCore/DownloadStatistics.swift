import Foundation

/// Aggregated download activity for insights panels and menu bar summaries.
public struct DownloadStatistics: Sendable, Equatable {
    public var totalCompletedBytes: Int64
    public var completedCount: Int
    public var failedCount: Int
    public var activeCount: Int
    public var queuedCount: Int
    public var bytesByCategory: [FileCategory: Int64]
    public var countByCategory: [FileCategory: Int]
    /// Top hosts by completed bytes, descending.
    public var topSources: [SourceSummary]

    public struct SourceSummary: Sendable, Equatable, Identifiable {
        public var host: String
        public var completedBytes: Int64
        public var downloadCount: Int
        public var id: String { host }
    }

    public static func compute(from downloads: [Download]) -> DownloadStatistics {
        var totalCompletedBytes: Int64 = 0
        var completedCount = 0
        var failedCount = 0
        var activeCount = 0
        var queuedCount = 0
        var bytesByCategory: [FileCategory: Int64] = [:]
        var countByCategory: [FileCategory: Int] = [:]
        var sourceBytes: [String: Int64] = [:]
        var sourceCount: [String: Int] = [:]

        for download in downloads where download.state != .cancelled {
            let category = FileCategory(fileName: download.fileName)
            countByCategory[category, default: 0] += 1
            switch download.state {
            case .completed:
                completedCount += 1
                let bytes = download.totalBytes ?? download.receivedBytes
                totalCompletedBytes += bytes
                bytesByCategory[category, default: 0] += bytes
                let host = DownloadSource.host(for: download.url)
                sourceBytes[host, default: 0] += bytes
                sourceCount[host, default: 0] += 1
            case .failed:
                failedCount += 1
            case .queued:
                queuedCount += 1
            case .probing, .downloading, .verifying, .paused:
                activeCount += 1
            case .cancelled:
                break
            }
        }

        let topSources = sourceBytes.keys.sorted { sourceBytes[$0, default: 0] > sourceBytes[$1, default: 0] }
            .prefix(8)
            .map { host in
                SourceSummary(host: host, completedBytes: sourceBytes[host, default: 0], downloadCount: sourceCount[host, default: 0])
            }

        return DownloadStatistics(
            totalCompletedBytes: totalCompletedBytes,
            completedCount: completedCount,
            failedCount: failedCount,
            activeCount: activeCount,
            queuedCount: queuedCount,
            bytesByCategory: bytesByCategory,
            countByCategory: countByCategory,
            topSources: Array(topSources)
        )
    }
}

/// Normalizes a download URL's host for grouping and filters.
public enum DownloadSource: Sendable {
    public static func host(for url: URL) -> String {
        url.host()?.lowercased() ?? String(localized: "Unknown host")
    }
}
