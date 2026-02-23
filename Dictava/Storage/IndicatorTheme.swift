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

// MARK: - Built-in Presets

extension IndicatorTheme {
    static let midnight = IndicatorTheme(
        id: "midnight",
        label: "Midnight",
        isBuiltIn: true,
        waveformColorHex: "#4A9EFF",
        backgroundColorHex: "#1a1a2e",
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
        waveformColorHex: "#00ff88",
        backgroundColorHex: "#1a1a2e",
        borderColorHex: "#00ff88",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.2,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let ember = IndicatorTheme(
        id: "ember",
        label: "Ember",
        isBuiltIn: true,
        waveformColorHex: "#FF6B35",
        backgroundColorHex: "#2d1b1b",
        borderColorHex: "#FF6B35",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.15,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let lilac = IndicatorTheme(
        id: "lilac",
        label: "Lilac",
        isBuiltIn: true,
        waveformColorHex: "#B07AFF",
        backgroundColorHex: "#1e1a2e",
        borderColorHex: "#B07AFF",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.15,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let frost = IndicatorTheme(
        id: "frost",
        label: "Frost",
        isBuiltIn: true,
        waveformColorHex: "#007AFF",
        backgroundColorHex: "#f0f0f5",
        borderColorHex: "#000000",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.1,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let slate = IndicatorTheme(
        id: "slate",
        label: "Slate",
        isBuiltIn: true,
        waveformColorHex: "#8899aa",
        backgroundColorHex: "#2c2f33",
        borderColorHex: "#ffffff",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.12,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let rose = IndicatorTheme(
        id: "rose",
        label: "Rose",
        isBuiltIn: true,
        waveformColorHex: "#ff6b8a",
        backgroundColorHex: "#2a1520",
        borderColorHex: "#ff6b8a",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.15,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let ocean = IndicatorTheme(
        id: "ocean",
        label: "Ocean",
        isBuiltIn: true,
        waveformColorHex: "#00d4aa",
        backgroundColorHex: "#0d1f2d",
        borderColorHex: "#00d4aa",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.15,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let solar = IndicatorTheme(
        id: "solar",
        label: "Solar",
        isBuiltIn: true,
        waveformColorHex: "#ffb830",
        backgroundColorHex: "#2a1f0d",
        borderColorHex: "#ffb830",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.15,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let mint = IndicatorTheme(
        id: "mint",
        label: "Mint",
        isBuiltIn: true,
        waveformColorHex: "#34c759",
        backgroundColorHex: "#e8f5e9",
        borderColorHex: "#000000",
        cornerRadius: 22,
        borderWidth: 1,
        borderOpacity: 0.1,
        horizontalPadding: 16,
        verticalPadding: 10,
        backgroundOpacity: 0.85
    )

    static let monochrome = IndicatorTheme(
        id: "monochrome",
        label: "Monochrome",
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

    static let allPresets: [IndicatorTheme] = [
        midnight, neon, ember, lilac, frost,
        slate, rose, ocean, solar, mint, monochrome
    ]
}

// MARK: - Random Generation

extension IndicatorTheme {
    static func randomized() -> IndicatorTheme {
        // Background: biased toward dark (more usable for floating indicator)
        let bgLightness = Double.random(in: 0.05...0.25)
        let bgHue = Double.random(in: 0...1)
        let bgSaturation = Double.random(in: 0.2...0.6)
        let bgColor = NSColor(hue: bgHue, saturation: bgSaturation, brightness: bgLightness, alpha: 1)

        // Waveform: vibrant, high saturation
        let wfHue = Double.random(in: 0...1)
        let wfSaturation = Double.random(in: 0.6...1.0)
        let wfBrightness = Double.random(in: 0.7...1.0)
        let wfColor = NSColor(hue: wfHue, saturation: wfSaturation, brightness: wfBrightness, alpha: 1)

        func hexFromNSColor(_ c: NSColor) -> String {
            guard let srgb = c.usingColorSpace(.sRGB) else { return "#ffffff" }
            let r = Int(min(255, max(0, round(srgb.redComponent * 255))))
            let g = Int(min(255, max(0, round(srgb.greenComponent * 255))))
            let b = Int(min(255, max(0, round(srgb.blueComponent * 255))))
            return String(format: "#%02x%02x%02x", r, g, b)
        }

        let waveformHex = hexFromNSColor(wfColor)

        return IndicatorTheme(
            id: UUID().uuidString,
            label: "New Theme",
            isBuiltIn: false,
            waveformColorHex: waveformHex,
            backgroundColorHex: hexFromNSColor(bgColor),
            borderColorHex: waveformHex,
            cornerRadius: Double(Int.random(in: 8...30)),
            borderWidth: Double([0, 0.5, 1, 1.5, 2].randomElement()!),
            borderOpacity: Double.random(in: 0.1...0.3),
            horizontalPadding: Double(Int.random(in: 10...22)),
            verticalPadding: Double(Int.random(in: 8...14)),
            backgroundOpacity: Double.random(in: 0.75...1.0)
        )
    }
}

// MARK: - Export / Import

extension IndicatorTheme {
    func exportCode() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "DT1:" + Data(json.utf8).base64EncodedString()
    }

    static func fromCode(_ code: String) -> IndicatorTheme? {
        guard code.hasPrefix("DT1:") else { return nil }
        let base64 = String(code.dropFirst(4))
        guard let data = Data(base64Encoded: base64),
              var theme = try? JSONDecoder().decode(IndicatorTheme.self, from: data) else { return nil }
        theme.id = UUID().uuidString
        theme.isBuiltIn = false
        return theme
    }
}

// MARK: - Resolve

extension IndicatorTheme {
    static func resolve(id: String, isDarkMode: Bool, customThemes: [IndicatorTheme] = []) -> IndicatorTheme {
        switch id {
        case "system":
            return isDarkMode ? .midnight : .frost
        default:
            if let preset = allPresets.first(where: { $0.id == id }) {
                return preset
            }
            if let custom = customThemes.first(where: { $0.id == id }) {
                return custom
            }
            return isDarkMode ? .midnight : .frost
        }
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
