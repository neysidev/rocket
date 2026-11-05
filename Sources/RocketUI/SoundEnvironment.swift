import SwiftUI

private struct SoundEffectsKey: EnvironmentKey {
    static let defaultValue: SoundManager? = nil
}

public extension EnvironmentValues {
    var soundEffects: SoundManager? {
        get { self[SoundEffectsKey.self] }
        set { self[SoundEffectsKey.self] = newValue }
    }
}

public extension View {
    func soundEffects(_ manager: SoundManager?) -> some View {
        environment(\.soundEffects, manager)
    }
}
