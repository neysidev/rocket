import Foundation
import RocketCore

/// URLSession adapter for `HTTPTransport`.
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// `GET` with `Range: bytes=0-0`, per TRD probe step 1.
    public func probe(_ url: URL) async throws -> RemoteFileInfo {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        let ranged = http.statusCode == 206
        let total: Int64? = ranged
            ? http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) }
            : (http.expectedContentLength >= 0 ? http.expectedContentLength : nil)

        return RemoteFileInfo(
            finalURL: http.url ?? url,
            totalBytes: total,
            acceptsRanges: ranged,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            suggestedFileName: http.suggestedFilename
        )
    }
}
