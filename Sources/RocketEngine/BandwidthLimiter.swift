/// Token bucket shared by every connection it covers (global, queue or one download). Workers take tokens
/// for each chunk before writing it; when the bucket is in debt they wait, their bodies fill up and the
/// network task is suspended, so the limit applies to the network, not just the disk.
public actor BandwidthLimiter {
    /// nil means unlimited.
    public private(set) var bytesPerSecond: Int64?
    private var tokens: Double = 0
    private var last = ContinuousClock.now
    /// Short burst allowance so chunk granularity does not starve the bucket.
    private let burst: Duration = .milliseconds(250)

    public init(bytesPerSecond: Int64? = nil) {
        self.bytesPerSecond = bytesPerSecond.flatMap { $0 > 0 ? $0 : nil }
    }

    public func setRate(_ bytesPerSecond: Int64?) {
        self.bytesPerSecond = bytesPerSecond.flatMap { $0 > 0 ? $0 : nil }
        tokens = 0
        last = .now
    }

    public func acquire(_ count: Int) async throws {
        guard let rate = bytesPerSecond.map(Double.init) else { return }
        let now = ContinuousClock.now
        let elapsed = now - last
        last = now
        tokens = min(rate * burst.seconds, tokens + rate * elapsed.seconds) - Double(count)
        if tokens < 0 {
            try await Task.sleep(for: .seconds(-tokens / rate))
        }
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
