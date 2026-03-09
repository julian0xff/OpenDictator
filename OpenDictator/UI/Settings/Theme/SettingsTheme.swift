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
        windowBackground: Color(hex: "#1C1C1E"),
        sidebarBackground: Color(hex: "#161618"),
        cardBackground: Color(hex: "#2C2C2E"),
        border: Color(hex: "#38383A"),
        textPrimary: Color(hex: "#F5F5F5"),
        textSecondary: Color(hex: "#98989D"),
        textTertiary: Color(hex: "#6C6C70"),
        controlAccent: Color(hex: "#0A84FF"),
        controlBackground: Color(hex: "#3A3A3C"),
        destructive: Color(hex: "#FF453A"),
        destructiveBackground: Color(hex: "#FF453A").opacity(0.12),
        infoBorder: Color(hex: "#48484A"),
        success: Color(hex: "#30D158"),
        successBackground: Color(hex: "#30D158").opacity(0.15),
        warning: Color(hex: "#FF9F0A"),
        warningBackground: Color(hex: "#FF9F0A").opacity(0.15),
        shadow: Color.black.opacity(0.4),
        isDark: true
    )

    static let light = SettingsTheme(
        windowBackground: Color(hex: "#F2F2F7"),
        sidebarBackground: Color(hex: "#F2F2F7"),
        cardBackground: Color(hex: "#FFFFFF"),
        border: Color(hex: "#E5E5EA"),
        textPrimary: Color(hex: "#1C1C1E"),
        textSecondary: Color(hex: "#6C6C70"),
        textTertiary: Color(hex: "#8E8E93"),
        controlAccent: Color(hex: "#007AFF"),
        controlBackground: Color(hex: "#E5E5EA"),
        destructive: Color(hex: "#FF3B30"),
        destructiveBackground: Color(hex: "#FF3B30").opacity(0.08),
        infoBorder: Color(hex: "#D1D1D6"),
        success: Color(hex: "#34C759"),
        successBackground: Color(hex: "#34C759").opacity(0.1),
        warning: Color(hex: "#FF9500"),
        warningBackground: Color(hex: "#FF9500").opacity(0.1),
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
        case .dark: return NSColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
        case .light: return NSColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)
        case .system:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
                : NSColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)
        }
    }
}
