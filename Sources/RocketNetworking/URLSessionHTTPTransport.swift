import Foundation
import RocketCore

/// URLSession adapter for `HTTPTransport`. Bodies arrive as `URLSessionDataDelegate` chunks, never byte by byte.
public final class URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .rocketDefault) {
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func probe(_ url: URL) async throws -> RemoteFileInfo {
        do {
            let response = try await fetch(url, range: ByteRange(start: 0, end: 0), ifRange: nil)
            return response.info // dropping `body` cancels the transfer
        } catch DownloadError.http(let status) where [405, 416, 501].contains(status) {
            return try await head(url)
        }
    }

    public func fetch(_ url: URL, range: ByteRange?, ifRange: String?) async throws -> TransferResponse {
        var request = URLRequest(url: url)
        if let range { request.setValue(range.headerValue, forHTTPHeaderField: "Range") }
        if let ifRange { request.setValue(ifRange, forHTTPHeaderField: "If-Range") }
        // Compressed bodies would break byte offsets.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                task.delegate = DataTaskDelegate(requestedRange: range, continuation: continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func head(_ url: URL) async throws -> RemoteFileInfo {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.network(code: URLError.badServerResponse.rawValue) }
        guard http.statusCode < 400 else { throw DownloadError.http(status: http.statusCode) }
        var info = RemoteFileInfo(http, fallbackURL: url)
        info.acceptsRanges = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
        return info
    }
}

public extension URLSessionConfiguration {
    /// No cache, no cookies stored, generous per-host connection limit for segmented downloads.
    static var rocketDefault: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 16
        configuration.timeoutIntervalForRequest = 30
        return configuration
    }
}

extension RemoteFileInfo {
    init(_ http: HTTPURLResponse, fallbackURL: URL) {
        let contentRangeTotal = http.value(forHTTPHeaderField: "Content-Range")?
            .split(separator: "/").last.flatMap { Int64($0) }
        let length = http.expectedContentLength >= 0 ? http.expectedContentLength : nil
        self.init(
            finalURL: http.url ?? fallbackURL,
            totalBytes: http.statusCode == 206 ? contentRangeTotal : length,
            acceptsRanges: http.statusCode == 206,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            suggestedFileName: http.suggestedFilename,
            contentType: http.mimeType
        )
    }
}

/// Bridges one data task's delegate callbacks to async/await.
/// `@unchecked Sendable`: URLSession calls a task's delegate serially on the session's delegate queue.
private final class DataTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let requestedRange: ByteRange?
    private var headers: CheckedContinuation<TransferResponse, any Error>?
    private let stream: AsyncThrowingStream<Data, any Error>
    private let body: AsyncThrowingStream<Data, any Error>.Continuation

    init(requestedRange: ByteRange?, continuation: CheckedContinuation<TransferResponse, any Error>) {
        self.requestedRange = requestedRange
        headers = continuation
        // ponytail: unbounded buffer; a disk slower than the network grows memory. Add backpressure
        // (suspend the task above 4 MiB buffered) when the engine measures it.
        (stream, body) = AsyncThrowingStream.makeStream()
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            fail(DownloadError.network(code: URLError.badServerResponse.rawValue))
            return completionHandler(.cancel)
        }
        guard http.statusCode < 400 else {
            fail(DownloadError.http(status: http.statusCode))
            return completionHandler(.cancel)
        }
        let bodyStart: Int64
        if http.statusCode == 206 {
            let start = http.value(forHTTPHeaderField: "Content-Range")
                .flatMap { $0.split(separator: " ").last?.split(separator: "-").first }
                .flatMap { Int64($0) }
            guard let start, start == requestedRange?.start else {
                fail(DownloadError.invalidRangeResponse)
                return completionHandler(.cancel)
            }
            bodyStart = start
        } else {
            bodyStart = 0
        }
        body.onTermination = { [weak dataTask] _ in dataTask?.cancel() }
        headers?.resume(returning: TransferResponse(
            statusCode: http.statusCode,
            info: RemoteFileInfo(http, fallbackURL: dataTask.originalRequest?.url ?? http.url!),
            bodyStart: bodyStart,
            body: stream
        ))
        headers = nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        body.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return body.finish() }
        fail(Self.map(error))
    }

    private func fail(_ error: any Error) {
        headers?.resume(throwing: error)
        headers = nil
        body.finish(throwing: error)
    }

    private static func map(_ error: any Error) -> any Error {
        guard let urlError = error as? URLError else { return error }
        return urlError.code == .cancelled ? CancellationError() : DownloadError.network(code: urlError.code.rawValue)
    }
}
