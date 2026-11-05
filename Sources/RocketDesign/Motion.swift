import SwiftUI

// Reusable transitions and animation helpers. Under Reduce Motion, motion collapses to short opacity fades.

@MainActor
public enum RocketTransition {
    /// List and grid item insert/remove.
    public static let list = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)).combined(with: .offset(y: -3)),
        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    )

    /// Swapping main content (settings page, add sheet phase, empty ↔ list).
    public static let content = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 4)),
        removal: .opacity.combined(with: .offset(y: -4))
    )

    /// Inline controls appearing (search field, filter chips, errors).
    public static let reveal = AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing))

    public static func adaptive(_ full: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : full
    }
}

private struct RocketAnimatedModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let full: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? RocketMotion.fast : full, value: value)
    }
}

private struct RocketTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let full: AnyTransition

    func body(content: Content) -> some View {
        content.transition(RocketTransition.adaptive(full, reduceMotion: reduceMotion))
    }
}

private struct RocketPressScaleModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pressed: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.scaleEffect(!reduceMotion && pressed ? scale : 1)
    }
}

public extension View {
    /// Animates `value` with `full`, or a short fade when Reduce Motion is on.
    func rocketAnimation<V: Equatable>(_ full: Animation, value: V) -> some View {
        modifier(RocketAnimatedModifier(full: full, value: value))
    }

    /// Applies a transition that becomes opacity-only under Reduce Motion.
    func rocketTransition(_ full: AnyTransition) -> some View {
        modifier(RocketTransitionModifier(full: full))
    }

    /// Press feedback without scaling when Reduce Motion is on.
    func rocketPressScale(_ pressed: Bool, scale: CGFloat = RocketMotion.pressScale) -> some View {
        modifier(RocketPressScaleModifier(pressed: pressed, scale: scale))
    }
}
