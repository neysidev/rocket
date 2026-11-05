import SwiftUI

/// Track + fill. Determinate only when the fraction is known; otherwise a static partial fill (no shimmer).
public struct RocketProgressBar: View {
    let fraction: Double?
    let tint: Color
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double?, tint: Color, height: CGFloat = RocketSize.progressBarRow) {
        self.fraction = fraction
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(RocketColor.chartTrack)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fraction == nil ? tint.opacity(0.35) : tint)
                        .frame(width: proxy.size.width * min(1, max(0, fraction ?? 1)))
                }
                // motion.progress: interpolate between 5 Hz updates; never ahead of real data.
                .animation(reduceMotion ? nil : RocketMotion.progress, value: fraction)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Rounded square with a monochrome type symbol (28 pt by default).
public struct FileTile: View {
    let symbol: String
    let size: CGFloat

    public init(symbol: String, size: CGFloat = RocketSize.fileTile) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(RocketColor.textSecondary)
            .frame(width: size, height: size)
            .background(RocketColor.control, in: RoundedRectangle(cornerRadius: size > RocketSize.fileTile ? RocketRadius.control : RocketRadius.small))
            .accessibilityHidden(true)
    }
}

/// Capsule filter pill: subtle fill at rest, one step up when selected.
public struct PillButtonStyle: ButtonStyle {
    let selected: Bool

    public init(selected: Bool) {
        self.selected = selected
    }

    public func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, selected: selected)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.rocketLabel)
                .foregroundStyle(selected || hovering ? RocketColor.textPrimary : RocketColor.textSecondary)
                .padding(.horizontal, RocketSpace.s4)
                .frame(height: 26)
                .background(selected ? RocketColor.fillSelected : hovering ? RocketColor.fillSubtle : RocketColor.fillSubtle.opacity(0.6), in: Capsule())
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(RocketMotion.fast, value: hovering)
                .animation(RocketMotion.fast, value: configuration.isPressed)
        }
    }
}

/// Circular icon button: no fill at rest, `surface.control` on hover, a deeper step when pressed.
public struct IconButtonStyle: ButtonStyle {
    let role: ButtonRole?

    public init(role: ButtonRole? = nil) {
        self.role = role
    }

    public func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, destructive: role == .destructive)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let destructive: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(destructive ? RocketColor.danger : hovering ? RocketColor.textPrimary : RocketColor.textSecondary)
                .frame(width: RocketSize.iconButton, height: RocketSize.iconButton)
                .background {
                    Circle()
                        .fill(RocketColor.control)
                        .opacity(configuration.isPressed ? 1 : hovering ? 0.7 : 0)
                }
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(RocketMotion.fast, value: hovering)
        }
    }
}

public extension ButtonStyle where Self == IconButtonStyle {
    static var rocketIcon: IconButtonStyle { IconButtonStyle() }
}
