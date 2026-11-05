import Foundation
import RocketCore

/// Maps download lifecycle events to sound effects. Pure logic for tests and `SoundManager`.
public enum SoundEffect: String, CaseIterable, Sendable {
    case downloadComplete
    case downloadFailed
    case queueFinished
    case downloadStarted
    case downloadPaused
    case downloadResumed
    case downloadAdded
    case warning
    case toggleOn

    var resourceName: String { rawValue }

    /// Playback level; kept low so effects sit under music and system UI.
    var volume: Float {
        switch self {
        case .downloadComplete, .queueFinished: 0.55
        case .downloadFailed, .warning: 0.5
        case .downloadAdded, .downloadStarted: 0.42
        case .downloadPaused, .downloadResumed: 0.38
        case .toggleOn: 0.35
        }
    }

    /// Minimum time before the same effect can play again (rapid polls, bulk pause).
    var cooldown: Duration {
        switch self {
        case .downloadStarted: .milliseconds(800)
        case .downloadPaused, .downloadResumed: .milliseconds(250)
        case .warning: .milliseconds(600)
        default: .milliseconds(180)
        }
    }
}

public enum SoundFeedback {
    public static func effect(for event: DownloadEvent) -> SoundEffect? {
        switch event {
        case .completed: .downloadComplete
        case .failed: .downloadFailed
        case .queueFinished: .queueFinished
        }
    }

    /// State transitions observed from agent snapshots (not fired on the first snapshot).
    public static func effect(id: UUID, from previous: DownloadState, to next: DownloadState, startedBefore: Set<UUID>) -> SoundEffect? {
        switch (previous, next) {
        case (.paused, .downloading): return .downloadResumed
        case (_, .downloading) where previous != .downloading && !startedBefore.contains(id): return .downloadStarted
        case (_, .paused): return .downloadPaused
        default: return nil
        }
    }
}
