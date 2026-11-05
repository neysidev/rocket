import Foundation

/// What a probe learns about a remote file.
public struct RemoteFileInfo: Sendable, Hashable {
    public var finalURL: URL
    public var totalBytes: Int64?
    public var acceptsRanges: Bool
    public var etag: String?
    public var lastModified: String?
    public var suggestedFileName: String?

    public init(finalURL: URL, totalBytes: Int64?, acceptsRanges: Bool, etag: String?, lastModified: String?, suggestedFileName: String?) {
        self.finalURL = finalURL
        self.totalBytes = totalBytes
        self.acceptsRanges = acceptsRanges
        self.etag = etag
        self.lastModified = lastModified
        self.suggestedFileName = suggestedFileName
    }
}

/// Networking port; URLSession adapter lives in RocketNetworking.
public protocol HTTPTransport: Sendable {
    func probe(_ url: URL) async throws -> RemoteFileInfo
}
