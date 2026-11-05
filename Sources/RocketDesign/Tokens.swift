import AppKit
import SwiftUI

// The only place raw color values are allowed. Values from docs/DESIGN.md.
// ponytail: colors defined in code (no asset catalog) because SPM without Xcode can't compile .xcassets;
// move to an asset catalog with High Contrast variants once the Xcode project exists.

private func dynamic(_ name: String, dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
    func rgb(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
    let color = NSColor(name: NSColor.Name(name)) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark, darkAlpha) : rgb(light, lightAlpha)
    }
    return Color(nsColor: color)
}

/// Graphite neutrals with one warm accent, Ember. Dark first; light is a warm paper counterpart.
public enum RocketColor {
    // Surfaces, back to front.
    public static let sidebar = dynamic("surface.sidebar", dark: 0x0C0C0E, light: 0xF3F2EF)
    public static let canvas = dynamic("surface.canvas", dark: 0x131315, light: 0xFCFCFB)
    /// Cards, inputs at rest, grouped settings.
    public static let raised = dynamic("surface.raised", dark: 0x19191C, light: 0xFFFFFF)
    /// Menus, modals, tooltips: always above everything else.
    public static let overlay = dynamic("surface.overlay", dark: 0x1D1D21, light: 0xFFFFFF)
    /// Input fill, segmented track, keycaps, file tiles.
    public static let control = dynamic("surface.control", dark: 0x232327, light: 0xF1F0ED)

    // State fills, layered over any surface.
    public static let hover = dynamic("fill.hover", dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.045, lightAlpha: 0.04)
    public static let selected = dynamic("fill.selected", dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.08, lightAlpha: 0.065)
    public static let scrim = dynamic("fill.scrim", dark: 0x000000, light: 0x18181A, darkAlpha: 0.5, lightAlpha: 0.22)

    // Strokes.
    public static let border = dynamic("stroke.border", dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.07, lightAlpha: 0.08)
    public static let borderStrong = dynamic("stroke.strong", dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.13, lightAlpha: 0.15)

    // Text.
    public static let textPrimary = dynamic("text.primary", dark: 0xEDEDEF, light: 0x1B1B1E)
    public static let textSecondary = dynamic("text.secondary", dark: 0x9D9DA6, light: 0x62626B)
    public static let textTertiary = dynamic("text.tertiary", dark: 0x66666E, light: 0x9B9BA3)
    /// Text and icons on the inverse fill (primary buttons, tooltips).
    public static let textInverse = dynamic("text.inverse", dark: 0x111113, light: 0xFCFCFB)
    public static let inverse = dynamic("fill.inverse", dark: 0xEDEDEF, light: 0x1B1B1E)

    // Ember: what is in flight now, focus, and the "on" state of controls. Never a button fill.
    public static let accent = dynamic("accent.ember", dark: 0xFF8A4C, light: 0xE5651F)
    /// Ember as text or small icons on light surfaces (4.5:1).
    public static let accentText = dynamic("accent.emberText", dark: 0xFF9C66, light: 0xB24A0E)
    public static let accentSoft = dynamic("accent.soft", dark: 0xFF8A4C, light: 0xE5651F, darkAlpha: 0.14, lightAlpha: 0.12)

    public static let success = dynamic("status.success", dark: 0x4CC38A, light: 0x1E8A56)
    public static let danger = dynamic("status.danger", dark: 0xF0565C, light: 0xCE3A40)
    public static let dangerSoft = dynamic("status.dangerSoft", dark: 0xF0565C, light: 0xCE3A40, darkAlpha: 0.14, lightAlpha: 0.1)
    public static let warning = dynamic("status.warning", dark: 0xE5B045, light: 0x956600)

    public static let chartNeutral = dynamic("chart.neutral", dark: 0x3A3A41, light: 0xD8D7D2)
    public static let track = dynamic("chart.track", dark: 0x26262B, light: 0xEAE9E5)
}

public enum RocketSpace {
    public static let s1: CGFloat = 2
    public static let s2: CGFloat = 4
    public static let s3: CGFloat = 8
    public static let s4: CGFloat = 12
    public static let s5: CGFloat = 16
    public static let s6: CGFloat = 24
    public static let s7: CGFloat = 32
}

public enum RocketRadius {
    public static let modal: CGFloat = 14
    public static let card: CGFloat = 10
    public static let control: CGFloat = 7
    public static let small: CGFloat = 5
}

public enum RocketSize {
    public static let control: CGFloat = 30
    public static let controlSmall: CGFloat = 24
    public static let iconButton: CGFloat = 26
    public static let fileTile: CGFloat = 28
    public static let fileTileRow: CGFloat = 34
    public static let fileTileCard: CGFloat = 52
    public static let row: CGFloat = 52
    public static let sidebarRow: CGFloat = 28
    public static let progressBarRow: CGFloat = 4
    public static let progressBarDetail: CGFloat = 6
    public static let keycapHeight: CGFloat = 18
    public static let sidebarWidth: CGFloat = 228
    public static let headerHeight: CGFloat = 52
    public static let menuBarPanelWidth: CGFloat = 360
}

public extension Font {
    static let rocketDisplay = Font.system(size: 22, weight: .semibold)
    static let rocketMetricLarge = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let rocketMetric = Font.system(size: 19, weight: .semibold).monospacedDigit()
    static let rocketTitle = Font.system(size: 15, weight: .semibold)
    static let rocketHeadline = Font.system(size: 13, weight: .medium)
    static let rocketBody = Font.system(size: 13)
    static let rocketLabel = Font.system(size: 12, weight: .medium)
    static let rocketCaption = Font.system(size: 11)
    /// Uppercase section labels ("QUEUES"); pair with `.rocketEyebrow()`.
    static let rocketEyebrow = Font.system(size: 10.5, weight: .semibold)
    static let rocketMono = Font.system(size: 11.5, design: .monospaced)
}

public extension View {
    /// Uppercase, tracked, tertiary: the label above a group.
    func rocketEyebrow() -> some View {
        font(.rocketEyebrow).tracking(0.6).textCase(.uppercase).foregroundStyle(RocketColor.textTertiary)
    }
}

public enum RocketMotion {
    /// Strong ease-out: instant response, soft landing. Hover, press, small reveals.
    public static let fast = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    /// Menus, popovers, modals entering.
    public static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    /// Leaving is quicker than arriving.
    public static let exit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    /// Things moving on screen (segmented thumb, switch knob).
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.86)
    public static let progress = Animation.linear(duration: 0.2)
    public static let pressScale: CGFloat = 0.97
}

public extension View {
    /// Raised card: fill, 1 pt border, card radius.
    func rocketCard(fill: Color = RocketColor.raised, radius: CGFloat = RocketRadius.card) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(RocketColor.border))
    }

    /// Floating surface (menus, modals, tooltips): overlay fill, strong border, two-layer shadow.
    func rocketFloating(radius: CGFloat = RocketRadius.card) -> some View {
        background(RocketColor.overlay, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(RocketColor.borderStrong))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
    }
}
