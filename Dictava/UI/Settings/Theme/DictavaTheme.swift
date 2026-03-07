import SwiftUI

// MARK: - Dictava Theme (Ember Dark)

struct DictavaTheme: Equatable {
    let bg: Color
    let surface: Color
    let surfaceHover: Color
    let border: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let accent: Color
    let accentHover: Color
    let accentDim: Color
    let success: Color
    let successDim: Color
    let warning: Color
    let warningDim: Color
    let destructive: Color
    let destructiveDim: Color
}

extension DictavaTheme {
    static let ember = DictavaTheme(
        bg: Color(hex: "#0C0C0C"),
        surface: Color(hex: "#161616"),
        surfaceHover: Color(hex: "#1C1C1C"),
        border: Color(hex: "#262626"),
        textPrimary: Color(hex: "#E8E8E8"),
        textSecondary: Color(hex: "#888888"),
        textMuted: Color(hex: "#555555"),
        accent: Color(hex: "#FF6B5A"),
        accentHover: Color(hex: "#FF7D6E"),
        accentDim: Color(hex: "#FF6B5A").opacity(0.15),
        success: Color(hex: "#34D399"),
        successDim: Color(hex: "#34D399").opacity(0.12),
        warning: Color(hex: "#FBBF24"),
        warningDim: Color(hex: "#FBBF24").opacity(0.12),
        destructive: Color(hex: "#EF4444"),
        destructiveDim: Color(hex: "#EF4444").opacity(0.10)
    )
}

// MARK: - Spacing & Radius

extension DictavaTheme {
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24

    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 10
    static let radiusLg: CGFloat = 14
}

// MARK: - Environment Key

private struct DictavaThemeKey: EnvironmentKey {
    static let defaultValue: DictavaTheme = .ember
}

extension EnvironmentValues {
    var theme: DictavaTheme {
        get { self[DictavaThemeKey.self] }
        set { self[DictavaThemeKey.self] = newValue }
    }
}
