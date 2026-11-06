import AppKit
import SwiftUI

// MARK: Buttons

/// Maps Rocket's button roles onto the system bezels: primary → prominent, secondary → bordered, ghost → borderless.
public struct RocketButtonStyle: PrimitiveButtonStyle {
    public enum Variant: Sendable { case primary, accent, secondary, ghost, danger }
    public enum Size: Sendable { case small, regular }

    let variant: Variant
    let size: Size

    public init(_ variant: Variant = .secondary, size: Size = .regular, fullWidth: Bool = false) {
        self.variant = variant
        self.size = size
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        let button = Button(configuration).controlSize(size == .small ? .small : .regular)
        switch variant {
        case .primary, .accent: button.buttonStyle(.borderedProminent)
        case .danger: button.buttonStyle(.borderedProminent).tint(.red)
        case .secondary: button.buttonStyle(.bordered)
        case .ghost: button.buttonStyle(.borderless)
        }
    }
}

public extension PrimitiveButtonStyle where Self == RocketButtonStyle {
    static var rocketPrimary: RocketButtonStyle { RocketButtonStyle(.primary) }
    static var rocketSecondary: RocketButtonStyle { RocketButtonStyle(.secondary) }
    static var rocketGhost: RocketButtonStyle { RocketButtonStyle(.ghost) }
}

/// Borderless icon-only button, the system's toolbar/inline look.
public struct IconButtonStyle: PrimitiveButtonStyle {
    let isActive: Bool

    public init(role: ButtonRole? = nil, isActive: Bool = false, size: CGFloat = 0) {
        self.isActive = isActive
    }

    public func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
}

public extension PrimitiveButtonStyle where Self == IconButtonStyle {
    static var rocketIcon: IconButtonStyle { IconButtonStyle() }
}

// MARK: Data display

/// System linear progress showing the real fraction only. An unknown size shows an empty track, never a sweep.
public struct RocketProgressBar: View {
    let fraction: Double?
    let tint: Color

    public init(fraction: Double?, tint: Color = RocketColor.accent, height: CGFloat = 0) {
        self.fraction = fraction
        self.tint = tint
    }

    public var body: some View {
        ProgressView(value: min(1, max(0, fraction ?? 0)))
            .progressViewStyle(.linear)
        .controlSize(.small)
        .tint(tint)
        .accessibilityHidden(true)
    }
}

/// System spinner.
public struct RocketSpinner: View {
    let size: CGFloat

    public init(size: CGFloat = 14, tint: Color = RocketColor.textSecondary) {
        self.size = size
    }

    public var body: some View {
        ProgressView().controlSize(size <= 12 ? .mini : size <= 16 ? .small : .regular)
    }
}

/// SF Symbol per download state.
public struct StatusGlyph: View {
    public enum Kind: Equatable, Sendable {
        case queued, active(Double?), verifying, paused(Double?), done, failed, cancelled
    }

    let kind: Kind
    let size: CGFloat

    public init(_ kind: Kind, size: CGFloat = 14) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .queued: "clock"
        case .active: "arrow.down.circle.fill"
        case .verifying: "checkmark.shield"
        case .paused: "pause.circle.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    public var color: Color { Self.color(for: kind) }

    public static func color(for kind: Kind) -> Color {
        switch kind {
        case .queued, .paused: RocketColor.textSecondary
        case .active, .verifying: RocketColor.accent
        case .done: RocketColor.success
        case .failed: RocketColor.danger
        case .cancelled: RocketColor.textTertiary
        }
    }
}

/// Monochrome type symbol.
public struct FileTile: View {
    let symbol: String
    let size: CGFloat

    public init(symbol: String, size: CGFloat = RocketSize.fileTile) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.6))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Keyboard shortcut hint ("⌘N").
public struct Keycap: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text).font(.callout).foregroundStyle(.tertiary).accessibilityHidden(true)
    }
}

/// The app icon.
public struct RocketMark: View {
    let size: CGFloat

    public init(size: CGFloat = 22) {
        self.size = size
    }

    public var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
