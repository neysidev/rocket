import Foundation
import RocketCore

/// Human units: decimal sizes like Finder, at most 3 significant digits for speeds.
public enum Format {
    public static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file, allowedUnits: .all, spellsOutZero: false))
    }

    public static func speed(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let digits = value >= 100 || unit == 0 ? 0 : value >= 10 ? 1 : 2
        return value.formatted(.number.precision(.fractionLength(digits))) + " " + units[unit]
    }

    /// "2 min left", "1 hr left", "45 sec left".
    public static func timeLeft(_ seconds: Double) -> String {
        let seconds = max(1, Int(seconds.rounded(.up)))
        let duration = Duration.seconds(seconds)
        let text = duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
        return String(localized: "\(text) left")
    }

    /// The metadata line under a row's file name.
    public static func detail(_ item: DownloadItem) -> String {
        let download = item.download
        let size = download.totalBytes.map(bytes)
        let progress = size.map { "\(bytes(download.receivedBytes)) of \($0)" } ?? bytes(download.receivedBytes)
        switch download.state {
        case .downloading:
            var parts = [progress]
            if item.speed > 0 { parts.append(speed(item.speed)) }
            if let left = item.secondsLeft { parts.append(timeLeft(left)) }
            return parts.joined(separator: " · ")
        case .queued, .probing: return size ?? String(localized: "Size unknown")
        case .paused, .verifying: return progress
        case .completed: return size ?? bytes(download.receivedBytes)
        case .failed: return download.failure?.userMessage ?? progress
        case .cancelled: return progress
        }
    }
}

public extension DownloadState {
    /// Status word shown next to color (status never relies on color alone).
    var title: String {
        switch self {
        case .queued: String(localized: "Queued")
        case .probing: String(localized: "Starting")
        case .downloading: String(localized: "Downloading")
        case .paused: String(localized: "Paused")
        case .verifying: String(localized: "Verifying")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    var isActive: Bool { [.queued, .probing, .downloading, .verifying].contains(self) }
}

public extension FileCategory {
    var symbol: String {
        switch self {
        case .video: "film"
        case .archive: "archivebox"
        case .document: "doc.text"
        case .app: "app.dashed"
        case .music: "music.note"
        case .image: "photo"
        case .other: "doc"
        }
    }
}
