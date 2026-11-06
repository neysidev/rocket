import AppKit
import SwiftUI

// Rocket follows the system: semantic AppKit colors (light, dark, high contrast, accent color all come for free),
// system text styles, and standard spacing. These names stay so screens read the same; the values are the system's.

public enum RocketColor {
    public static let sidebar = Color(nsColor: .windowBackgroundColor)
    public static let canvas = Color(nsColor: .windowBackgroundColor)
    /// Cards, grouped content.
    public static let raised = Color(nsColor: .controlBackgroundColor)
    public static let overlay = Color(nsColor: .controlBackgroundColor)
    /// Subtle fill behind tiles and tracks.
    public static let control = Color(nsColor: .quaternarySystemFill)

    public static let hover = Color(nsColor: .quinarySystemFill)
    public static let selected = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    public static let scrim = Color.black.opacity(0.25)

    public static let border = Color(nsColor: .separatorColor)
    public static let borderStrong = Color(nsColor: .separatorColor)

    public static let textPrimary = Color(nsColor: .labelColor)
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    public static let textInverse = Color(nsColor: .alternateSelectedControlTextColor)
    public static let inverse = Color(nsColor: .labelColor)

    /// The user's system accent color.
    public static let accent = Color.accentColor
    public static let accentText = Color.accentColor
    public static let accentSoft = Color.accentColor.opacity(0.15)

    public static let success = Color(nsColor: .systemGreen)
    public static let danger = Color(nsColor: .systemRed)
    public static let dangerSoft = Color(nsColor: .systemRed).opacity(0.12)
    public static let warning = Color(nsColor: .systemOrange)

    public static let chartNeutral = Color(nsColor: .tertiaryLabelColor)
    public static let track = Color(nsColor: .quaternaryLabelColor)
}

public enum RocketSpace {
    public static let s1: CGFloat = 2
    public static let s2: CGFloat = 4
    public static let s3: CGFloat = 8
    public static let s4: CGFloat = 12
    public static let s5: CGFloat = 16
    public static let s6: CGFloat = 20
    public static let s7: CGFloat = 24
}

public enum RocketRadius {
    public static let modal: CGFloat = 10
    public static let card: CGFloat = 8
    public static let control: CGFloat = 6
    public static let small: CGFloat = 5
}

public enum RocketSize {
    public static let fileTile: CGFloat = 28
    public static let fileTileRow: CGFloat = 18
    public static let fileTileCard: CGFloat = 40
    /// Menu-bar rows.
    public static let row: CGFloat = 44
    public static let tableRow: CGFloat = 24
    public static let menuBarPanelWidth: CGFloat = 340
}

public extension Font {
    static let rocketDisplay = Font.title.weight(.semibold)
    static let rocketMetricLarge = Font.title.weight(.semibold).monospacedDigit()
    static let rocketMetric = Font.title2.weight(.semibold).monospacedDigit()
    static let rocketTitle = Font.title3.weight(.semibold)
    static let rocketHeadline = Font.headline
    static let rocketBody = Font.body
    static let rocketLabel = Font.callout
    static let rocketCaption = Font.caption
    static let rocketEyebrow = Font.subheadline.weight(.semibold)
    static let rocketMono = Font.system(.callout, design: .monospaced)
}

public extension View {
    /// Group label, as in grouped forms.
    func rocketEyebrow() -> some View {
        font(.rocketEyebrow).foregroundStyle(.secondary)
    }

    /// Grouped-content box: control background with a hairline, like a grouped form section.
    func rocketCard(fill: Color = RocketColor.raised, radius: CGFloat = RocketRadius.card) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(RocketColor.border.opacity(0.6)))
    }
}

public enum RocketMotion {
    public static let fast = Animation.easeOut(duration: 0.15)
    public static let standard = Animation.easeInOut(duration: 0.2)
    public static let enter = Animation.easeOut(duration: 0.2)
    public static let exit = Animation.easeIn(duration: 0.12)
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.86)
    public static let progress = Animation.linear(duration: 0.2)
    /// Duration of the quiet success tint on progress when a download completes.
    public static let completionFlash: Duration = .seconds(2)
}
