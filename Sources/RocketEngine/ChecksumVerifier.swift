import CryptoKit
import Foundation
import RocketCore

/// Hashes finished files for checksum verification (FR-ENG-10).
public enum ChecksumVerifier {
    /// Lowercase hex digest of the file. Nonisolated async, so a multi-gigabyte hash runs on the global executor,
    /// not on the scheduler actor; it stops early if the download is paused or cancelled.
    public static func digest(_ algorithm: Checksum.Algorithm, of url: URL) async throws -> String {
        switch algorithm {
        case .md5: try hash(Insecure.MD5(), url)
        case .sha1: try hash(Insecure.SHA1(), url)
        case .sha256: try hash(SHA256(), url)
        }
    }

    private static func hash<H: HashFunction>(_ hasher: H, _ url: URL) throws -> String {
        var hasher = hasher
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
