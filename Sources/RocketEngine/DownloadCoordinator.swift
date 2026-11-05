import Foundation
import RocketCore

/// Runs one download: owns its segment plan and runs segment workers in a task group.
///
/// Segmented mode (size known, ranges supported): N workers, each streaming one range with `If-Range`;
/// when a worker finishes it takes over half of the largest remaining segment. Otherwise one stream.
public actor DownloadCoordinator {
    public let url: URL
    public let info: RemoteFileInfo
    private let file: PartFile
    private let transport: any HTTPTransport
    private let planner: SegmentPlanner
    private let connections: Int
    private let checkpointInterval: Duration
    private let onCheckpoint: (@Sendable ([Segment]) async throws -> Void)?
    private let retry: RetryPolicy

    public private(set) var segments: [Segment]
    private var active: Set<Int> = []
    /// Simultaneous connections; lowered when the server rate-limits us (FR-ENG-12).
    public private(set) var connectionLimit: Int

    public init(
        url: URL, info: RemoteFileInfo, file: PartFile, segments: [Segment] = [],
        connections: Int, transport: any HTTPTransport, planner: SegmentPlanner = SegmentPlanner(),
        retry: RetryPolicy = RetryPolicy(),
        checkpointInterval: Duration = .seconds(2),
        onCheckpoint: (@Sendable ([Segment]) async throws -> Void)? = nil
    ) {
        self.retry = retry
        connectionLimit = max(1, connections)
        self.checkpointInterval = checkpointInterval
        self.onCheckpoint = onCheckpoint
        self.url = url
        self.info = info
        self.file = file
        self.transport = transport
        self.planner = planner
        self.connections = max(1, connections)
        self.segments = segments
    }

    public nonisolated var isSegmented: Bool { info.acceptsRanges && info.totalBytes != nil }

    public var receivedBytes: Int64 { segments.reduce(0) { $0 + $1.received } }

    /// Known up front, or learned when a stream of unknown length ends.
    public var totalBytes: Int64? {
        if let total = info.totalBytes { return total }
        if let segment = segments.first, segment.isComplete { return segment.end + 1 }
        return nil
    }

    /// Downloads every remaining byte into the part file. Cancelling the calling task stops all workers;
    /// `segments` keeps how far each one got, and a final checkpoint records it.
    public func run() async throws {
        do {
            try await transferAll()
            try await checkpoint()
        } catch {
            try? await checkpoint()
            throw error
        }
    }

    /// Captures progress, makes those bytes durable, then records them. The database never claims
    /// bytes the disk lacks: segments are read before `fsync`, so they can only under-report.
    public nonisolated func checkpoint() async throws {
        guard let onCheckpoint else { return }
        let snapshot = await segments
        try file.sync()
        try await onCheckpoint(snapshot)
    }

    private func transferAll() async throws {
        if segments.isEmpty || !isSegmented && segments.contains(where: { !$0.isComplete }) {
            // Without range support a single stream must restart from byte 0.
            segments = isSegmented
                ? planner.initialSegments(totalBytes: info.totalBytes!, connections: connections)
                : [info.totalBytes.map { Segment(start: 0, end: $0 - 1) } ?? .open()]
        }
        connectionLimit = isSegmented ? min(connectionLimit, connections) : 1

        let ticker = -1
        try await withThrowingTaskGroup(of: Int.self) { group in
            if onCheckpoint != nil {
                // ponytail: time-based only (every 2 s); add the TRD's 8 MiB trigger if crash re-downloads matter.
                group.addTask { [checkpointInterval] in
                    while (try? await Task.sleep(for: checkpointInterval)) != nil {
                        try await self.checkpoint()
                    }
                    return ticker
                }
            }
            while active.count < connectionLimit, let index = claimSegment() {
                group.addTask { try await self.transferWithRetry(index); return index }
            }
            if active.isEmpty { group.cancelAll() } // nothing left to fetch
            while let finished = try await group.next() {
                guard finished != ticker else { continue }
                active.remove(finished)
                while active.count < connectionLimit, let index = claimSegment() {
                    group.addTask { try await self.transferWithRetry(index); return index }
                }
                if active.isEmpty { group.cancelAll() } // stops the ticker
            }
        }

        guard segments.allSatisfy(\.isComplete) else {
            throw DownloadError.network(code: URLError.networkConnectionLost.rawValue)
        }
    }

    /// Picks an unstarted segment, or splits the largest active one.
    private func claimSegment() -> Int? {
        if let index = segments.indices.first(where: { !segments[$0].isComplete && !active.contains($0) }) {
            active.insert(index)
            return index
        }
        guard isSegmented, let split = planner.split(segments, candidates: active) else { return nil }
        segments[split.index].end = split.shortenedEnd
        segments.append(split.newSegment)
        active.insert(segments.count - 1)
        return segments.count - 1
    }

    /// Records progress and returns the segment's current end, which a split may have moved.
    private func advance(_ index: Int, to offset: Int64) -> Int64 {
        let segment = segments[index]
        segments[index].received = min(offset, segment.end + 1) - segment.start
        return segments[index].end
    }

    /// The server pushed back: drop one connection. Returns true if this worker should hand its segment back.
    private func backOff(_ index: Int) -> Bool {
        connectionLimit = max(1, connectionLimit - 1)
        return active.count > connectionLimit
    }

    /// A stream of unknown length ended cleanly: its last byte is the file's last byte.
    private func closeOpenSegment(_ index: Int, at offset: Int64) {
        segments[index].end = offset - 1
    }

    private func segment(_ index: Int) -> Segment { segments[index] }

    /// Retries transient failures with backoff. Attempts reset whenever a try made progress, so a long
    /// download on a flaky link is not failed by drops hours apart.
    private nonisolated func transferWithRetry(_ index: Int) async throws {
        var attempt = 0
        while true {
            let before = await segment(index).received
            do {
                return try await transfer(index)
            } catch let error as DownloadError where error.kind == .transient {
                attempt = await segment(index).received > before ? 1 : attempt + 1
                guard attempt < retry.maxAttempts else { throw error }
                // Rate-limited: free this connection; the segment is picked up again when a slot opens.
                if error.isRateLimit, await backOff(index) { return }
                try await retry.sleep(retry.delay(forAttempt: attempt))
            }
        }
    }

    /// Streams one segment into the file. Runs off the actor; only bookkeeping hops onto it.
    private nonisolated func transfer(_ index: Int) async throws {
        let segment = await segment(index)
        let response = try await transport.fetch(
            url,
            range: isSegmented ? ByteRange(start: segment.next, end: segment.end) : nil,
            ifRange: isSegmented ? info.validator : nil
        )
        // A full-body answer to an If-Range request means the file changed on the server.
        if isSegmented, !response.isPartial { throw DownloadError.remoteFileChanged }

        var offset = response.bodyStart
        var end = segment.end
        for try await chunk in response.body {
            try Task.checkCancellation()
            let count = Int(min(Int64(chunk.count), end - offset + 1))
            guard count > 0 else { return }
            // ponytail: pwrite on the cooperative pool; move to a dedicated I/O executor if profiling shows stalls.
            try file.write(count == chunk.count ? chunk : chunk.prefix(count), at: offset)
            offset += Int64(count)
            end = await advance(index, to: offset)
            if offset > end { return } // another worker took over the rest
        }
        if info.totalBytes == nil {
            await closeOpenSegment(index, at: offset)
        } else if offset <= end {
            throw DownloadError.network(code: URLError.networkConnectionLost.rawValue)
        }
    }
}
