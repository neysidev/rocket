import RocketCore
import Testing

@Test func legalTransitions() {
    #expect(DownloadState.queued.canTransition(to: .probing))
    #expect(DownloadState.downloading.canTransition(to: .paused))
    #expect(DownloadState.paused.canTransition(to: .cancelled))
}

@Test func illegalTransitions() {
    #expect(!DownloadState.queued.canTransition(to: .completed))
    #expect(!DownloadState.completed.canTransition(to: .cancelled))
}
