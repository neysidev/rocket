import RocketCore
import RocketEngine
import Testing

@Suite struct SegmentPlannerTests {
    let planner = SegmentPlanner()
    let mib = SegmentPlanner.mebibyte

    @Test func splitsEvenlyAndCoversEveryByte() {
        let segments = planner.initialSegments(totalBytes: 100 * mib + 7, connections: 8)
        #expect(segments.count == 8)
        #expect(segments.first?.start == 0)
        #expect(segments.last?.end == 100 * mib + 6)
        for (a, b) in zip(segments, segments.dropFirst()) { #expect(a.end + 1 == b.start) }
    }

    @Test func smallFilesUseFewerConnections() {
        #expect(planner.initialSegments(totalBytes: 3 * mib, connections: 8).count == 3)
        #expect(planner.initialSegments(totalBytes: 100, connections: 8).count == 1)
        #expect(planner.initialSegments(totalBytes: 0, connections: 8).isEmpty)
    }

    @Test func splitTakesUpperHalfOfLargestRemainder() throws {
        let segments = [
            Segment(start: 0, end: 10 * mib - 1, received: 9 * mib),
            Segment(start: 10 * mib, end: 20 * mib - 1, received: 2 * mib),
        ]
        let split = try #require(planner.split(segments, candidates: [0, 1]))
        #expect(split.index == 1)
        #expect(split.newSegment.start == 16 * mib)
        #expect(split.shortenedEnd == 16 * mib - 1)
        #expect(split.newSegment.end == 20 * mib - 1)
    }

    @Test func doesNotSplitSmallRemainders() {
        let segments = [Segment(start: 0, end: 2 * mib - 1)]
        #expect(planner.split(segments, candidates: [0]) == nil)
    }
}
