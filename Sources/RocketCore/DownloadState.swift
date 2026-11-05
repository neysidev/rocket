import Foundation

/// Lifecycle of a download. Illegal states are unrepresentable; transitions are checked by `canTransition(to:)`.
public enum DownloadState: String, Codable, Sendable, CaseIterable {
    case queued
    case probing
    case downloading
    case paused
    case verifying
    case completed
    case failed
    case cancelled

    /// Allowed transitions. Any state may move to `.cancelled`.
    public func canTransition(to next: DownloadState) -> Bool {
        if next == .cancelled { return self != .completed && self != .cancelled }
        switch (self, next) {
        case (.queued, .probing),
             (.probing, .downloading), (.probing, .failed), (.probing, .paused),
             (.downloading, .paused), (.downloading, .verifying), (.downloading, .failed),
             (.paused, .queued),
             (.verifying, .completed), (.verifying, .failed),
             (.failed, .queued):
            return true
        default:
            return false
        }
    }
}
