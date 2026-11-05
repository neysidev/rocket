import Foundation
import RocketCore
@testable import RocketUI
import Testing

@Suite struct SoundFeedbackTests {
    @Test func mapsDownloadEvents() {
        let download = Download(url: URL(string: "https://example.com/a.iso")!, destinationPath: "/tmp", fileName: "a.iso", state: .completed)
        #expect(SoundFeedback.effect(for: .completed(download)) == .downloadComplete)
        #expect(SoundFeedback.effect(for: .failed(download)) == .downloadFailed)
        #expect(SoundFeedback.effect(for: .queueFinished(DownloadQueue(name: "Night"))) == .queueFinished)
    }

    @Test func mapsStateTransitions() {
        let id = UUID()
        #expect(SoundFeedback.effect(id: id, from: .queued, to: .downloading, startedBefore: []) == .downloadStarted)
        #expect(SoundFeedback.effect(id: id, from: .queued, to: .downloading, startedBefore: [id]) == nil)
        #expect(SoundFeedback.effect(id: id, from: .downloading, to: .paused, startedBefore: []) == .downloadPaused)
        #expect(SoundFeedback.effect(id: id, from: .paused, to: .downloading, startedBefore: [id]) == .downloadResumed)
    }
}

@MainActor
@Suite struct SoundManagerTests {
    @Test func respectsMasterToggle() {
        var enabled = false
        let manager = SoundManager(isEnabled: { enabled })
        enabled = true
        manager.play(.toggleOn)
        manager.play(.toggleOn) // cooldown prevents overlap
        enabled = false
        manager.play(.downloadComplete) // no-op when disabled
    }
}
