import Foundation
import Network
import os

/// Development-only HTTP/1.1 server for engine and networking tests. Never ships.
///
/// Routes:
/// - `GET|HEAD /file/<size>` serves `size` deterministic bytes (see `byte(at:version:)`).
///   Query options:
///   - `version=v`: content seed; changes the ETag, Last-Modified and bytes (simulates a changed file).
///   - `ranges=0`: ignore `Range` and omit `Accept-Ranges`.
///   - `length=0`: omit `Content-Length` (body delimited by connection close).
///   - `name=f.iso`: send `Content-Disposition: attachment; filename="f.iso"`.
///   - `fail=<status>&failCount=N`: the first N requests for this exact URL return `status` (default N=1).
///   - `dropAt=<offset>&dropCount=N`: the first N requests close the connection once the body reaches
///     absolute file offset `offset` (default N=1).
///   - `delayMs=ms`: pause between 64 KiB chunks (slow server); with `delayFrom=<offset>` only from that offset on.
/// - `GET /redirect?to=<path>` answers `302` to `to`.
public final class RocketTestServer: Sendable {
    public let port: UInt16
    private let listener: NWListener

    struct State {
        var counts: [String: Int] = [:]
        var version = "1"
    }

    /// Request counts and current content version; a lock because Network.framework calls back on a dispatch queue.
    private let counts: OSAllocatedUnfairLock<State>

    public init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "RocketTestServer")
        let counts = OSAllocatedUnfairLock(initialState: State())
        self.listener = listener
        self.counts = counts

        port = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let resumeOnce: @Sendable (Result<UInt16, any Error>) -> Void = { result in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: resumeOnce(.success(listener.port?.rawValue ?? 0))
                case .failed(let error): resumeOnce(.failure(error))
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                Self.receive(connection, buffer: Data(), queue: queue, counts: counts)
            }
            listener.start(queue: queue)
        }
    }

    deinit {
        listener.cancel()
    }

    public func url(_ pathAndQuery: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(pathAndQuery)")!
    }

    /// Number of requests the server has received for `pathAndQuery`.
    public func requestCount(_ pathAndQuery: String) -> Int {
        counts.withLock { $0.counts[pathAndQuery, default: 0] }
    }

    /// Changes the bytes, ETag and Last-Modified served for URLs without a `version` query (simulates a re-upload).
    public func setVersion(_ version: String) {
        counts.withLock { $0.version = version }
    }

    // MARK: Content

    /// Byte at `offset` for a given version. Non-periodic so misplaced segments are detected.
    public static func byte(at offset: Int64, version: String = "1") -> UInt8 {
        let seed = version.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return UInt8(truncatingIfNeeded: ((UInt64(offset) &* 0x9E37_79B9_7F4A_7C15) ^ seed) >> 29)
    }

    public static func content(offset: Int64 = 0, count: Int, version: String = "1") -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { buffer in
            for i in 0..<count { buffer[i] = byte(at: offset + Int64(i), version: version) }
        }
        return data
    }

    public static func etag(version: String) -> String { "\"v\(version)\"" }

    // MARK: HTTP

    private static func receive(_ connection: NWConnection, buffer: Data, queue: DispatchQueue, counts: OSAllocatedUnfairLock<State>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                respond(connection, head: head, queue: queue, counts: counts)
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                receive(connection, buffer: buffer, queue: queue, counts: counts)
            }
        }
    }

    private static func respond(_ connection: NWConnection, head: String, queue: DispatchQueue, counts: OSAllocatedUnfairLock<State>) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2, let components = URLComponents(string: "http://x\(requestLine[1])") else {
            return send(connection, status: 400, headers: [:])
        }
        let method = String(requestLine[0])
        let target = String(requestLine[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let (count, currentVersion) = counts.withLock { state in
            state.counts[target, default: 0] += 1
            return (state.counts[target]!, state.version)
        }

        if components.path == "/redirect", let to = query["to"] {
            return send(connection, status: 302, headers: ["Location": to])
        }
        let parts = components.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "file", let size = Int64(parts[1]) else {
            return send(connection, status: 404, headers: [:])
        }
        if let fail = query["fail"].flatMap(Int.init), count <= Int(query["failCount"] ?? "1") ?? 1 {
            return send(connection, status: fail, headers: ["Retry-After": "0"])
        }

        let version = query["version"] ?? currentVersion
        let etag = etag(version: version)
        let lastModified = "Wed, 01 Jan 2025 00:00:\(String(format: "%02d", version.utf8.reduce(0) { $0 + Int($1) } % 60)) GMT"
        let rangesEnabled = query["ranges"] != "0"

        var start: Int64 = 0
        var end: Int64 = size - 1
        var status = 200
        if rangesEnabled, let range = headers["range"], range.hasPrefix("bytes=") {
            let ifRange = headers["if-range"]
            if ifRange == nil || ifRange == etag || ifRange == lastModified {
                let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
                let lower = Int64(bounds.first ?? "") ?? 0
                let upper = bounds.count > 1 ? Int64(bounds[1]) ?? size - 1 : size - 1
                guard lower < size else {
                    return send(connection, status: 416, headers: ["Content-Range": "bytes */\(size)"])
                }
                start = lower
                end = min(upper, size - 1)
                status = 206
            }
        }

        var responseHeaders = [
            "ETag": etag,
            "Last-Modified": lastModified,
            "Content-Type": "application/octet-stream",
        ]
        if rangesEnabled { responseHeaders["Accept-Ranges"] = "bytes" }
        if query["length"] != "0" { responseHeaders["Content-Length"] = String(max(0, end - start + 1)) }
        if status == 206 { responseHeaders["Content-Range"] = "bytes \(start)-\(end)/\(size)" }
        if let name = query["name"] { responseHeaders["Content-Disposition"] = "attachment; filename=\"\(name)\"" }

        let dropAt = query["dropAt"].flatMap(Int64.init).flatMap { offset in
            // Only responses whose body spans the drop point, and only the first `dropCount` requests.
            start <= offset && offset <= end && count <= Int(query["dropCount"] ?? "1") ?? 1 ? offset : nil
        }
        let body = method == "HEAD" ? nil : BodyPlan(
            offset: start, end: end, version: version, dropAt: dropAt,
            delay: .milliseconds(Int(query["delayMs"] ?? "0") ?? 0),
            delayFrom: Int64(query["delayFrom"] ?? "0") ?? 0
        )
        send(connection, status: status, headers: responseHeaders, body: body, queue: queue)
    }

    private struct BodyPlan: Sendable {
        var offset: Int64
        let end: Int64
        let version: String
        let dropAt: Int64?
        let delay: DispatchTimeInterval
        let delayFrom: Int64
    }

    private static func send(
        _ connection: NWConnection, status: Int, headers: [String: String],
        body: BodyPlan? = nil, queue: DispatchQueue? = nil
    ) {
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        var headers = headers
        headers["Connection"] = "close"
        if body == nil, headers["Content-Length"] == nil { headers["Content-Length"] = "0" }
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { error in
            guard error == nil else { return connection.cancel() }
            if let body, let queue {
                sendBody(connection, plan: body, queue: queue)
            } else {
                finish(connection)
            }
        })
    }

    private static func sendBody(_ connection: NWConnection, plan: BodyPlan, queue: DispatchQueue) {
        let limit = plan.dropAt.map { min($0, plan.end + 1) } ?? plan.end + 1
        guard plan.offset < limit else {
            // Done, or reached the drop point: closing early leaves the body short of Content-Length.
            return finish(connection)
        }
        let count = Int(min(65_536, limit - plan.offset))
        let data = content(offset: plan.offset, count: count, version: plan.version)
        connection.send(content: data, completion: .contentProcessed { error in
            guard error == nil else { return connection.cancel() }
            var next = plan
            next.offset += Int64(count)
            if plan.delay == .milliseconds(0) || plan.offset < plan.delayFrom {
                sendBody(connection, plan: next, queue: queue)
            } else {
                queue.asyncAfter(deadline: .now() + plan.delay) { sendBody(connection, plan: next, queue: queue) }
            }
        })
    }

    private static func finish(_ connection: NWConnection) {
        // Send FIN, then wait for the client to close: cancelling right away can reset the connection
        // and lose the tail of the body still in flight.
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
        })
    }
}
