import SwiftUI

struct IndicatorTheme: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var isBuiltIn: Bool

    // Colors (stored as hex strings for Codable)
    var waveformColorHex: String
    var backgroundColorHex: String
    var borderColorHex: String

    // Shape
    var cornerRadius: Double
    var borderWidth: Double
    var borderOpacity: Double
    var horizontalPadding: Double
    var verticalPadding: Double

    // Behavior
    var backgroundOpacity: Double

    // Computed color accessors
    var waveformColor: Color { Color(hex: waveformColorHex) }
    var backgroundColor: Color { Color(hex: backgroundColorHex) }
    var borderColor: Color { Color(hex: borderColorHex) }
}

// MARK: - Text Color (WCAG luminance)

extension Color {
    var relativeLuminance: Double {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return 0 }
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linearize(components.redComponent)
        let g = linearize(components.greenComponent)
        let b = linearize(components.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    var isLight: Bool { relativeLuminance > 0.5 }
}

extension IndicatorTheme {
    var textColor: Color {
        backgroundColor.isLight
            ? Color(white: 0.15)
            : Color(white: 0.85)
    }
}

// MARK: - Built-in Presets (4 only)

extension IndicatorTheme {
    static let ember = IndicatorTheme(
        id: "ember",
        label: "Ember",
        isBuiltIn: true,
        waveformColorHex: "#FF6B5A",
        backgroundColorHex: "#1A0F0D",
        borderColorHex: "#FF6B5A",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.15,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let midnight = IndicatorTheme(
        id: "midnight",
        label: "Midnight",
        isBuiltIn: true,
        waveformColorHex: "#4A9EFF",
        backgroundColorHex: "#1A1A2E",
        borderColorHex: "#ffffff",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.15,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let neon = IndicatorTheme(
        id: "neon",
        label: "Neon",
        isBuiltIn: true,
        waveformColorHex: "#00FF88",
        backgroundColorHex: "#1A1A2E",
        borderColorHex: "#00FF88",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.2,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let monochrome = IndicatorTheme(
        id: "monochrome",
        label: "Mono",
        isBuiltIn: true,
        waveformColorHex: "#ffffff",
        backgroundColorHex: "#000000",
        borderColorHex: "#ffffff",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.2,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let allPresets: [IndicatorTheme] = [ember, midnight, neon, monochrome]
}

// MARK: - Resolve

extension IndicatorTheme {
    static func resolve(id: String, isDarkMode: Bool = true, customThemes: [IndicatorTheme] = []) -> IndicatorTheme {
        if let preset = allPresets.first(where: { $0.id == id }) {
            return preset
        }
        return .ember
    }
}

// MARK: - Color ↔ Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#ffffff" }
        let r = Int(min(255, max(0, round(components.redComponent * 255))))
        let g = Int(min(255, max(0, round(components.greenComponent * 255))))
        let b = Int(min(255, max(0, round(components.blueComponent * 255))))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
