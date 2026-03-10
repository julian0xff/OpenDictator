import SwiftUI

// MARK: - Settings Theme

struct SettingsTheme: Equatable {
    // Backgrounds
    let windowBackground: Color
    let sidebarBackground: Color
    let cardBackground: Color

    // Borders
    let border: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let sectionHeader: Color

    // Controls
    let controlAccent: Color
    let controlBackground: Color
    let selectedBackground: Color

    // Semantic
    let destructive: Color
    let destructiveBackground: Color
    let infoBorder: Color
    let success: Color
    let successBackground: Color
    let warning: Color
    let warningBackground: Color
    let shadow: Color
}

// MARK: - Warm Theme (Single Theme)

extension SettingsTheme {
    static let warm = SettingsTheme(
        windowBackground: Color(hex: "#F5F1EC"),
        sidebarBackground: Color(hex: "#EDE8E1"),
        cardBackground: Color(hex: "#FEFCFA"),
        border: Color(hex: "#E5DFD8"),
        textPrimary: Color(hex: "#2D2A26"),
        textSecondary: Color(hex: "#7A756E"),
        textTertiary: Color(hex: "#A09A93"),
        sectionHeader: Color(hex: "#B5AFA8"),
        controlAccent: Color(hex: "#C4703E"),
        controlBackground: Color(hex: "#DED8D0"),
        selectedBackground: Color(hex: "#FEF7F2"),
        destructive: Color(hex: "#C8503C"),
        destructiveBackground: Color(hex: "#C8503C").opacity(0.15),
        infoBorder: Color(hex: "#E5DFD8"),
        success: Color(hex: "#6B9E7A"),
        successBackground: Color(hex: "#F0F7F2"),
        warning: Color(hex: "#D4960A"),
        warningBackground: Color(hex: "#D4960A").opacity(0.1),
        shadow: Color.black.opacity(0.04)
    )

    /// Always returns the warm theme — appearance parameter kept for source compatibility.
    static func resolve(colorScheme: ColorScheme, appearance: SettingsAppearance) -> SettingsTheme {
        .warm
    }
}

// MARK: - Spacing & Radius Constants

extension SettingsTheme {
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    static let radiusSm: CGFloat = 8     // buttons, inputs
    static let radiusMd: CGFloat = 10    // sidebar items
    static let radiusLg: CGFloat = 12    // cards
    static let radiusXl: CGFloat = 12    // large cards
    static let radiusPill: CGFloat = 99  // badges, toggles
}

// MARK: - Environment Key

private struct SettingsThemeKey: EnvironmentKey {
    static let defaultValue: SettingsTheme = .warm
}

extension EnvironmentValues {
    var settingsTheme: SettingsTheme {
        get { self[SettingsThemeKey.self] }
        set { self[SettingsThemeKey.self] = newValue }
    }
}

// MARK: - Settings Appearance (kept for source compat — always uses warm theme)

enum SettingsAppearance: String, CaseIterable {
    case system
    case dark
    case light

    /// Always returns light appearance to match the warm theme.
    var nsAppearance: NSAppearance? {
        NSAppearance(named: .aqua)
    }

    /// Always returns warm window background.
    var windowBackgroundColor: NSColor {
        NSColor(red: 245/255, green: 241/255, blue: 236/255, alpha: 1) // #F5F1EC
    }
}
