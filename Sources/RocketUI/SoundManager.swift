import AppKit
import Foundation
import os
import RocketCore

/// Central playback for Rocket's UI and download feedback sounds.
@MainActor
public final class SoundManager {
    private let isEnabled: () -> Bool
    private let log = Rocket.logger("Sound")
    private var assets: [SoundEffect: NSSound] = [:]
    private var lastPlayed: [SoundEffect: ContinuousClock.Instant] = [:]
    /// Avoid replaying "started" when a download re-enters `.downloading` after pause.
    private var startedDownloads = Set<UUID>()

    public init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        preload()
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled { play(.toggleOn) }
    }

    public func play(_ effect: SoundEffect) {
        guard isEnabled() else { return }
        let now = ContinuousClock.now
        if let last = lastPlayed[effect], now - last < effect.cooldown { return }
        guard let sound = assets[effect] else {
            log.error("Missing sound asset \(effect.resourceName, privacy: .public)")
            return
        }
        lastPlayed[effect] = now
        sound.stop()
        sound.volume = effect.volume
        if !sound.play() {
            log.error("Could not play \(effect.resourceName, privacy: .public)")
        }
    }

    public func handle(_ event: DownloadEvent) {
        guard let effect = SoundFeedback.effect(for: event) else { return }
        play(effect)
    }

    public func handleTransition(id: UUID, from previous: DownloadState, to next: DownloadState) {
        if next == .cancelled || next == .completed || next == .failed { startedDownloads.remove(id) }
        guard let effect = SoundFeedback.effect(id: id, from: previous, to: next, startedBefore: startedDownloads) else { return }
        if effect == .downloadStarted { startedDownloads.insert(id) }
        play(effect)
    }

    public func pruneStarted(excluding ids: Set<UUID>) {
        startedDownloads.formIntersection(ids)
    }

    public func playAdded() { play(.downloadAdded) }
    public func playWarning() { play(.warning) }

    private func preload() {
        for effect in SoundEffect.allCases {
            guard let url = Bundle.module.url(forResource: effect.resourceName, withExtension: "wav", subdirectory: "Sounds") else { continue }
            assets[effect] = NSSound(contentsOf: url, byReference: true)
        }
    }
}
