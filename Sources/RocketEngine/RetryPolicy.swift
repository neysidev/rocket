import RocketCore

/// Exponential backoff with jitter for transient failures (TRD: 1 s base, 60 s cap, 5 attempts).
public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// Injectable so tests run without real waiting.
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        maxAttempts: Int = 5, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(60),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.sleep = sleep
    }

    /// Upper bound of the wait before retry number `attempt` (1-based): base · 2^(attempt-1), capped.
    public func ceiling(forAttempt attempt: Int) -> Duration {
        min(maxDelay, baseDelay * (1 << min(max(0, attempt - 1), 30)))
    }

    /// A random wait in `[ceiling/2, ceiling]`, so many connections do not retry in lockstep.
    public func delay(forAttempt attempt: Int) -> Duration {
        let ceiling = ceiling(forAttempt: attempt)
        return ceiling / 2 + ceiling / 2 * Double.random(in: 0...1)
    }

    public init(defaults: RocketDefaults) {
        self.init(
            maxAttempts: defaults.retryMaxAttempts,
            baseDelay: .seconds(defaults.retryBaseDelaySeconds),
            maxDelay: .seconds(defaults.retryMaxDelaySeconds)
        )
    }
}
