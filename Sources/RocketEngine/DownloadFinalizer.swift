import Darwin
import Foundation
import RocketCore

/// Turns a finished `.rocketpart` into the user's file: verify, fsync, atomic rename, Gatekeeper metadata.
public enum DownloadFinalizer {
    /// Returns where the file landed. Never overwrites: an existing name gets " 2", " 3", … like Finder.
    public static func finalize(
        _ file: PartFile, expectedBytes: Int64, folder: URL, fileName: String, source: URL, now: Date = .now
    ) throws -> URL {
        let actual = try file.size()
        guard actual == expectedBytes else { throw DownloadError.sizeMismatch(expected: expectedBytes, actual: actual) }
        try file.sync()

        let name = FileNameSanitizer.sanitize(fileName)
        for attempt in 1...999 {
            let candidate = folder.appending(path: attempt == 1 ? name : numbered(name, attempt))
            guard FileNameSanitizer.isInside(candidate, folder: folder) else {
                throw DownloadError.destinationNotWritable(path: candidate.path)
            }
            if renamex_np(file.url.path, candidate.path, UInt32(RENAME_EXCL)) == 0 {
                markDownloaded(candidate, from: source, at: now)
                return candidate
            }
            guard errno == EEXIST else { throw PartFile.error(errno, path: candidate.path) }
        }
        throw DownloadError.destinationNotWritable(path: folder.path)
    }

    /// "ubuntu.iso" → "ubuntu 2.iso" (numbers go before the last extension).
    static func numbered(_ name: String, _ number: Int) -> String {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
    }

    /// Quarantine flag (Gatekeeper checks the file on first open) and "Where from" in Finder's Get Info.
    static func markDownloaded(_ url: URL, from source: URL, at date: Date) {
        let quarantine = String(format: "0081;%08x;Rocket Downloader;", Int(date.timeIntervalSince1970))
        setAttribute("com.apple.quarantine", Data(quarantine.utf8), on: url)
        if let whereFroms = try? PropertyListSerialization.data(fromPropertyList: [source.absoluteString], format: .binary, options: 0) {
            setAttribute("com.apple.metadata:kMDItemWhereFroms", whereFroms, on: url)
        }
    }

    private static func setAttribute(_ name: String, _ value: Data, on url: URL) {
        _ = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, $0.count, 0, 0) }
    }
}
