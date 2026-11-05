import Foundation

/// What the server says about a remote file.
public struct RemoteFileInfo: Sendable, Hashable, Codable {
    /// URL after redirects.
    public var finalURL: URL
    /// Full file size, when the server states it.
    public var totalBytes: Int64?
    /// The server honored a range request (`206`).
    public var acceptsRanges: Bool
    public var etag: String?
    public var lastModified: String?
    /// From `Content-Disposition`, else the URL's last path component.
    public var suggestedFileName: String?
    public var contentType: String?

    public init(
        finalURL: URL, totalBytes: Int64?, acceptsRanges: Bool, etag: String? = nil,
        lastModified: String? = nil, suggestedFileName: String? = nil, contentType: String? = nil
    ) {
        self.finalURL = finalURL
        self.totalBytes = totalBytes
        self.acceptsRanges = acceptsRanges
        self.etag = etag
        self.lastModified = lastModified
        self.suggestedFileName = suggestedFileName
        self.contentType = contentType
    }

    /// Validator for `If-Range`: the strong ETag if any, else Last-Modified.
    public var validator: String? {
        if let etag, !etag.hasPrefix("W/") { return etag }
        return lastModified
    }
}

/// Inclusive byte range; `end == nil` means "to the end of the file".
public struct ByteRange: Sendable, Hashable, Codable {
    public var start: Int64
    public var end: Int64?

    public init(start: Int64, end: Int64?) {
        self.start = start
        self.end = end
    }

    public var headerValue: String { "bytes=\(start)-\(end.map(String.init) ?? "")" }
}

/// Response head plus a body delivered in chunks as they arrive.
public struct TransferResponse: Sendable {
    public var statusCode: Int
    public var info: RemoteFileInfo
    /// First byte offset of the body: the `Content-Range` start for `206`, else 0.
    public var bodyStart: Int64
    /// Cancelling iteration (or dropping the body) cancels the request.
    public var body: HTTPBody

    public init(statusCode: Int, info: RemoteFileInfo, bodyStart: Int64, body: HTTPBody) {
        self.statusCode = statusCode
        self.info = info
        self.bodyStart = bodyStart
        self.body = body
    }

    public var isPartial: Bool { statusCode == 206 }
}

/// Networking port; the URLSession adapter lives in RocketNetworking, fakes in tests.
public protocol HTTPTransport: Sendable {
    /// `GET` with `Range: bytes=0-0`, falling back to `HEAD` when the server rejects it.
    func probe(_ url: URL) async throws -> RemoteFileInfo
    /// Starts a request and returns once headers arrive. Throws `DownloadError.http` for 4xx/5xx.
    func fetch(_ url: URL, range: ByteRange?, ifRange: String?) async throws -> TransferResponse
}
