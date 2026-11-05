import Foundation

/// A checksum the user expects the finished file to match (FR-ENG-10).
public struct Checksum: Codable, Sendable, Hashable {
    public enum Algorithm: String, Codable, Sendable, CaseIterable {
        case md5, sha1, sha256

        public var title: String {
            switch self {
            case .md5: "MD5"
            case .sha1: "SHA-1"
            case .sha256: "SHA-256"
            }
        }

        var hexLength: Int {
            switch self {
            case .md5: 32
            case .sha1: 40
            case .sha256: 64
            }
        }
    }

    public var algorithm: Algorithm
    /// Lowercase hex.
    public var value: String

    public init(algorithm: Algorithm, value: String) {
        self.algorithm = algorithm
        self.value = value.lowercased()
    }

    /// `sha256:ab12…`, `sha-1=…`, or bare hex (the algorithm is inferred from its length). nil if malformed.
    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        let parts = text.split(maxSplits: 1, whereSeparator: { $0 == ":" || $0 == "=" }).map(String.init)
        let hex = (parts.last ?? "").lowercased()
        guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else { return nil }
        let algorithm: Algorithm?
        if parts.count == 2 {
            algorithm = Algorithm(rawValue: parts[0].lowercased().replacingOccurrences(of: "-", with: ""))
        } else {
            algorithm = Algorithm.allCases.first { $0.hexLength == hex.count }
        }
        guard let algorithm, hex.count == algorithm.hexLength else { return nil }
        self.init(algorithm: algorithm, value: hex)
    }
}
