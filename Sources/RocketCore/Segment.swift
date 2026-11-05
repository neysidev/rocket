/// One byte range of a file, downloaded over its own connection. `end` is inclusive.
public struct Segment: Sendable, Hashable, Codable {
    public var start: Int64
    public var end: Int64
    /// Bytes durably written from `start`.
    public var received: Int64

    public init(start: Int64, end: Int64, received: Int64 = 0) {
        self.start = start
        self.end = end
        self.received = received
    }

    /// Next byte offset to fetch.
    public var next: Int64 { start + received }
    public var remaining: Int64 { max(0, end - next + 1) }
    public var isComplete: Bool { remaining == 0 }

    /// Segment covering a file of unknown size (single stream until the server closes).
    public static func open(from start: Int64 = 0) -> Segment {
        Segment(start: start, end: .max - 1)
    }
}
