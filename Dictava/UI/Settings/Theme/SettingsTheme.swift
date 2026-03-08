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

    // Controls
    let controlAccent: Color
    let controlBackground: Color

    // Semantic
    let destructive: Color
    let destructiveBackground: Color
    let infoBorder: Color
    let success: Color
    let successBackground: Color
    let warning: Color
    let warningBackground: Color
    let shadow: Color

    // Whether this is a dark theme
    let isDark: Bool
}

// MARK: - Presets

extension SettingsTheme {
    static let dark = SettingsTheme(
        windowBackground: Color(hex: "#09090b"),
        sidebarBackground: Color(hex: "#09090b"),
        cardBackground: Color(hex: "#18181b"),
        border: Color(hex: "#27272a"),
        textPrimary: Color(hex: "#fafafa"),
        textSecondary: Color(hex: "#a1a1aa"),
        textTertiary: Color(hex: "#71717a"),
        controlAccent: .white,
        controlBackground: Color(hex: "#27272a"),
        destructive: Color(hex: "#ef4444"),
        destructiveBackground: Color(hex: "#ef4444").opacity(0.1),
        infoBorder: Color(hex: "#3f3f46"),
        success: Color(hex: "#22c55e"),
        successBackground: Color(hex: "#22c55e").opacity(0.15),
        warning: Color(hex: "#f59e0b"),
        warningBackground: Color(hex: "#f59e0b").opacity(0.15),
        shadow: Color.black.opacity(0.4),
        isDark: true
    )

    static let light = SettingsTheme(
        windowBackground: Color(hex: "#ffffff"),
        sidebarBackground: Color(hex: "#fafafa"),
        cardBackground: Color(hex: "#ffffff"),
        border: Color(hex: "#e4e4e7"),
        textPrimary: Color(hex: "#09090b"),
        textSecondary: Color(hex: "#52525b"),
        textTertiary: Color(hex: "#71717a"),
        controlAccent: Color(hex: "#18181b"),
        controlBackground: Color(hex: "#f4f4f5"),
        destructive: Color(hex: "#ef4444"),
        destructiveBackground: Color(hex: "#ef4444").opacity(0.06),
        infoBorder: Color(hex: "#e4e4e7"),
        success: Color(hex: "#16a34a"),
        successBackground: Color(hex: "#16a34a").opacity(0.1),
        warning: Color(hex: "#d97706"),
        warningBackground: Color(hex: "#d97706").opacity(0.1),
        shadow: Color.black.opacity(0.08),
        isDark: false
    )

    static func resolve(colorScheme: ColorScheme, appearance: SettingsAppearance) -> SettingsTheme {
        switch appearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return colorScheme == .dark ? .dark : .light
        }
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

    static let radiusSm: CGFloat = 4
    static let radiusMd: CGFloat = 6
    static let radiusLg: CGFloat = 8
    static let radiusXl: CGFloat = 12
}

// MARK: - Environment Key

private struct SettingsThemeKey: EnvironmentKey {
    static let defaultValue: SettingsTheme = .dark
}

extension EnvironmentValues {
    var settingsTheme: SettingsTheme {
        get { self[SettingsThemeKey.self] }
        set { self[SettingsThemeKey.self] = newValue }
    }
}

// MARK: - Settings Appearance

enum SettingsAppearance: String, CaseIterable {
    case system
    case dark
    case light

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    var windowBackgroundColor: NSColor {
        switch self {
        case .dark: return NSColor(red: 9/255, green: 9/255, blue: 11/255, alpha: 1)
        case .light: return .white
        case .system:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(red: 9/255, green: 9/255, blue: 11/255, alpha: 1)
                : .white
        }
    }
}
