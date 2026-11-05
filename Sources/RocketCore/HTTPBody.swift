import Foundation
import os

/// A response body delivered in chunks, with backpressure: when more than `highWater` bytes wait unread,
/// the producer is asked to pause (URLSession task suspended, so TCP flow control slows the server) and is
/// resumed once the reader drains below `lowWater`. Dropping the body or cancelling the reading task cancels it.
public final class HTTPBody: AsyncSequence, Sendable {
    public typealias Element = Data

    public struct Control: Sendable {
        public var pause: @Sendable () -> Void
        public var resume: @Sendable () -> Void
        public var cancel: @Sendable () -> Void

        public init(pause: @escaping @Sendable () -> Void, resume: @escaping @Sendable () -> Void, cancel: @escaping @Sendable () -> Void) {
            self.pause = pause
            self.resume = resume
            self.cancel = cancel
        }
    }

    private struct State {
        var chunks: [Data] = []
        var buffered = 0
        var finished = false
        var error: (any Error)?
        var waiter: CheckedContinuation<Data?, any Error>?
        var paused = false
        var control: Control?
    }

    public let highWater: Int
    public let lowWater: Int
    /// Lock rather than actor: the producer is URLSession's delegate queue and must not hop.
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(highWater: Int = 4 << 20, lowWater: Int = 1 << 20) {
        self.highWater = highWater
        self.lowWater = lowWater
    }

    deinit {
        state.withLock { $0.control }?.cancel()
    }

    public func setControl(_ control: Control) {
        state.withLock { $0.control = control }
    }

    // MARK: Producer

    public func yield(_ data: Data) {
        let (waiter, pause) = state.withLock { state -> (CheckedContinuation<Data?, any Error>?, (@Sendable () -> Void)?) in
            if let waiter = state.waiter {
                state.waiter = nil
                return (waiter, nil)
            }
            state.chunks.append(data)
            state.buffered += data.count
            guard state.buffered > highWater, !state.paused else { return (nil, nil) }
            state.paused = true
            return (nil, state.control?.pause)
        }
        waiter?.resume(returning: data)
        pause?()
    }

    public func finish(throwing error: (any Error)? = nil) {
        let waiter = state.withLock { state -> CheckedContinuation<Data?, any Error>? in
            guard !state.finished else { return nil }
            state.finished = true
            state.error = error
            defer { state.waiter = nil }
            return state.waiter
        }
        if let error { waiter?.resume(throwing: error) } else { waiter?.resume(returning: nil) }
    }

    /// Bytes received but not yet read.
    public var bufferedBytes: Int { state.withLock { $0.buffered } }

    // MARK: Consumer

    func next() async throws -> Data? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let (action, resume) = state.withLock { state -> (Result<Data?, any Error>?, (@Sendable () -> Void)?) in
                    if !state.chunks.isEmpty {
                        let chunk = state.chunks.removeFirst()
                        state.buffered -= chunk.count
                        var resume: (@Sendable () -> Void)?
                        if state.paused, state.buffered < lowWater {
                            state.paused = false
                            resume = state.control?.resume
                        }
                        return (.success(chunk), resume)
                    }
                    if let error = state.error { return (.failure(error), nil) }
                    if state.finished { return (.success(nil), nil) }
                    state.waiter = continuation
                    return (nil, nil)
                }
                resume?()
                if let action { continuation.resume(with: action) }
            }
        } onCancel: {
            let (waiter, cancel) = state.withLock { state in
                defer { state.waiter = nil }
                return (state.waiter, state.control?.cancel)
            }
            cancel?()
            waiter?.resume(throwing: CancellationError())
        }
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        let body: HTTPBody
        public mutating func next() async throws -> Data? { try await body.next() }
    }

    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(body: self) }
}
