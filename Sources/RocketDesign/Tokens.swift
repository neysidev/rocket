import AppKit
import SwiftUI

// The only place raw color values are allowed. Values from the Rocket Design System.
// ponytail: colors defined in code (no asset catalog) because SPM without Xcode can't compile .xcassets;
// move to an asset catalog with High Contrast variants once the Xcode project exists.

private func dynamic(_ name: String, dark: UInt32, light: UInt32) -> Color {
    func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
    let color = NSColor(name: NSColor.Name(name)) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
    }
    return Color(nsColor: color)
}

public enum RocketColor {
    public static let canvas = dynamic("surface.canvas", dark: 0x121417, light: 0xF7F8FA)
    public static let panel = dynamic("surface.panel", dark: 0x1B1E22, light: 0xEEF0F2)
    public static let card = dynamic("surface.card", dark: 0x24282D, light: 0xFFFFFF)
    public static let cardSelected = dynamic("surface.cardSelected", dark: 0x2D3238, light: 0xFFFFFF)
    public static let control = dynamic("surface.control", dark: 0x2A2E34, light: 0xE6E8EB)
    public static let hairline = Color.primary.opacity(0.08)
    /// Pill rest / hover fill and the selected pill or card.
    public static let fillSubtle = Color.primary.opacity(0.05)
    public static let fillSelected = Color.primary.opacity(0.12)

    public static let textPrimary = dynamic("text.primary", dark: 0xF3F4F6, light: 0x17191C)
    public static let textSecondary = dynamic("text.secondary", dark: 0xA1A7AF, light: 0x5F656D)
    public static let textTertiary = dynamic("text.tertiary", dark: 0x6E747C, light: 0x8E949B)

    public static let flame = dynamic("accent.flame", dark: 0xFFB23F, light: 0xF29D0B)
    public static let flameText = dynamic("accent.flameText", dark: 0xFFB23F, light: 0x9A5B00)
    public static let interactive = Color.accentColor
    /// Main window accent: active progress, live numbers, selection tint.
    public static let accent = dynamic("accent.blue", dark: 0x4C8DFF, light: 0x1F6FEB)

    public static let success = dynamic("status.success", dark: 0x6FCF8A, light: 0x23843E)
    public static let danger = dynamic("status.danger", dark: 0xFF6B63, light: 0xD7342B)
    public static let warning = dynamic("status.warning", dark: 0xF5C451, light: 0xA86F00)

    public static let chartNeutral = dynamic("chart.neutral", dark: 0x5C626A, light: 0xC3C8CE)
    public static let chartTrack = dynamic("chart.track", dark: 0x33383E, light: 0xE1E4E8)
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
    public static let panel: CGFloat = 20
    public static let card: CGFloat = 12
    public static let control: CGFloat = 8
    public static let small: CGFloat = 6
}

public enum RocketSize {
    public static let iconButton: CGFloat = 28
    public static let fileTile: CGFloat = 28
    public static let fileTileRow: CGFloat = 40
    public static let fileTileCard: CGFloat = 56
    public static let rowCompact: CGFloat = 36
    public static let row: CGFloat = 52
    public static let progressBarRow: CGFloat = 3
    public static let progressBarDetail: CGFloat = 6
    public static let keycapHeight: CGFloat = 20
    public static let sidebarWidth: CGFloat = 220
    public static let inspectorWidth: CGFloat = 300
    public static let menuBarPanelWidth: CGFloat = 360
}

public extension Font {
    static let rocketMetricLarge = Font.system(size: 28, weight: .semibold).monospacedDigit()
    static let rocketMetric = Font.system(size: 20, weight: .semibold).monospacedDigit()
    static let rocketTitle = Font.system(size: 15, weight: .semibold)
    static let rocketHeadline = Font.system(size: 13, weight: .semibold)
    static let rocketBody = Font.system(size: 13)
    static let rocketLabel = Font.system(size: 12, weight: .medium)
    static let rocketCaption = Font.system(size: 11)
    static let rocketMono = Font.system(size: 12, design: .monospaced)
}

public enum RocketMotion {
    public static let fast = Animation.easeOut(duration: 0.12)
    public static let standard = Animation.easeInOut(duration: 0.22)
    public static let glass = Animation.spring(response: 0.35, dampingFraction: 0.85)
    public static let progress = Animation.linear(duration: 0.2)
}

public extension View {
    /// Liquid Glass on macOS 26+, system material before that. Chrome/controls only, never content.
    @ViewBuilder
    func rocketGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(RocketColor.hairline, lineWidth: 1))
        }
    }
}
