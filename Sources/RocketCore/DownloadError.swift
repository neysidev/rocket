import Foundation

/// Every way a download can fail, grouped by how the engine reacts (TRD: Error classes).
public enum DownloadError: Error, Sendable, Hashable, Codable {
    case http(status: Int)
    /// A `URLError` code (timeout, connection lost, offline, …).
    case network(code: Int)
    /// The server copy changed since the download started (ETag / Last-Modified mismatch).
    case remoteFileChanged
    /// The server returned the wrong bytes for a range (bad `Content-Range`).
    case invalidRangeResponse
    case sizeMismatch(expected: Int64, actual: Int64)
    case diskFull
    case destinationNotWritable(path: String)
    case invalidURL
    case io(errno: Int32)

    public enum Kind: Sendable {
        /// Retry with backoff; resume when the network returns.
        case transient
        /// Stop with a reason and a fix-it action.
        case needsUser
        /// Stop immediately; retrying will not help.
        case fatal
    }

    public var kind: Kind {
        switch self {
        case .http(let status):
            switch status {
            case 408, 425, 429, 500...599: .transient
            case 401, 403, 407, 410: .needsUser
            default: .fatal
            }
        case .network(let code):
            // URLError codes that mean "the request itself is bad", not "the network hiccupped".
            [-1000, -1002, -1202, -1203, -1204, -1206].contains(code) ? .fatal : .transient
        case .remoteFileChanged, .diskFull: .needsUser
        case .invalidRangeResponse: .transient
        case .sizeMismatch, .destinationNotWritable, .invalidURL, .io: .fatal
        }
    }

    /// The server asked us to back off (fewer connections, longer wait).
    public var isRateLimit: Bool {
        if case .http(let status) = self { return status == 429 || status == 503 }
        return false
    }
}

public extension DownloadError {
    /// The one place failures become user-facing text (TRD: errors mapped in one place, localized).
    var userMessage: String {
        switch self {
        case .http(let status):
            switch status {
            case 401, 403: String(localized: "The server refused access (\(status)). Sign in and try again.")
            case 404: String(localized: "The file was not found on the server (404).")
            case 410: String(localized: "The link has expired (410).")
            case 429, 503: String(localized: "The server is busy (\(status)).")
            default: String(localized: "The server responded with error \(status).")
            }
        case .network: String(localized: "The network connection was lost.")
        case .remoteFileChanged: String(localized: "The file changed on the server, so the download restarted.")
        case .invalidRangeResponse: String(localized: "The server sent unexpected data.")
        case .sizeMismatch: String(localized: "The downloaded file has the wrong size.")
        case .diskFull: String(localized: "The disk is full.")
        case .destinationNotWritable: String(localized: "Rocket can't write to the destination folder.")
        case .invalidURL: String(localized: "Only http and https links are supported.")
        case .io(let code): String(localized: "A file error occurred (\(code)).")
        }
    }
}
