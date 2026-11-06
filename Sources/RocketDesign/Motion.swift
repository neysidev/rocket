import SwiftUI

// Reusable transitions and animation helpers. Under Reduce Motion, motion collapses to short opacity fades.

@MainActor
public enum RocketTransition {
    public static let list = AnyTransition.opacity
    public static let content = AnyTransition.opacity
    public static let reveal = AnyTransition.opacity
}

private struct RocketAnimatedModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let full: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : full, value: value)
    }
}

public extension View {
    /// Animates `value` with `full`; no animation when Reduce Motion is on.
    func rocketAnimation<V: Equatable>(_ full: Animation, value: V) -> some View {
        modifier(RocketAnimatedModifier(full: full, value: value))
    }

    func rocketTransition(_ full: AnyTransition) -> some View {
        transition(full)
    }
}
