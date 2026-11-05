import RocketCore

/// Dynamic segmentation (ADR 0006): equal initial split, then idle connections take half of the largest remainder.
public struct SegmentPlanner: Sendable {
    public static let mebibyte: Int64 = 1 << 20

    /// Smallest initial segment; small files use fewer connections.
    public var minimumSegment: Int64 = mebibyte
    /// A segment is split only if more than this remains.
    public var minimumSplit: Int64 = 2 * mebibyte

    public init() {}

    public func initialSegments(totalBytes: Int64, connections: Int) -> [Segment] {
        guard totalBytes > 0 else { return [] }
        let count = Int(max(1, min(Int64(max(1, connections)), totalBytes / minimumSegment)))
        let size = totalBytes / Int64(count)
        return (0..<count).map { index in
            let start = Int64(index) * size
            let end = index == count - 1 ? totalBytes - 1 : start + size - 1
            return Segment(start: start, end: end)
        }
    }

    /// Splits the largest segment among `candidates` at the midpoint of what it has left.
    /// Returns the shortened segment's index and the new upper-half segment, or nil if nothing is worth splitting.
    public func split(_ segments: [Segment], candidates: some Sequence<Int>) -> (index: Int, shortenedEnd: Int64, newSegment: Segment)? {
        guard let index = candidates.max(by: { segments[$0].remaining < segments[$1].remaining }),
              segments[index].remaining > minimumSplit
        else { return nil }
        let segment = segments[index]
        let middle = segment.next + segment.remaining / 2
        return (index, middle - 1, Segment(start: middle, end: segment.end))
    }
}
