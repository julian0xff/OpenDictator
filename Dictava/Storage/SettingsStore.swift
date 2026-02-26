import SwiftUI
import Combine

enum IndicatorMode: String, CaseIterable, Identifiable {
    case floating, notch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floating: return "Floating Pill"
        case .notch: return "Notch"
        }
    }

    var sfSymbol: String {
        switch self {
        case .floating: return "capsule"
        case .notch: return "rectangle.topthird.inset.filled"
        }
    }
}

enum NotchAnimationSpeed: String, CaseIterable, Identifiable {
    case normal, relaxed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .relaxed: return "Relaxed"
        }
    }
}

enum NotchExpansionStyle: String, CaseIterable, Identifiable {
    case down, horizontal, both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .down: return "Down"
        case .horizontal: return "Horizontal"
        case .both: return "Both"
        }
    }

    var sfSymbol: String {
        switch self {
        case .down: return "arrow.down.to.line"
        case .horizontal: return "arrow.left.and.right"
        case .both: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

final class SettingsStore: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("selectedModelName") var selectedModelName = "openai_whisper-tiny.en"
    @AppStorage("silenceTimeoutSeconds") var silenceTimeoutSeconds = 5.0
    @AppStorage("removeFillerWords") var removeFillerWords = true
    @AppStorage("autoCapitalize") var autoCapitalize = true
    @AppStorage("autoPunctuation") var autoPunctuation = true
    @AppStorage("playStartStopSounds") var playStartStopSounds = true
    @AppStorage("showFloatingIndicator") var showFloatingIndicator = true
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("llmEnabled") var llmEnabled = false
    @AppStorage("selectedLLMModel") var selectedLLMModel = ""
    @AppStorage("showDockIcon") var showDockIcon = false
    @AppStorage("selectedLanguage") var selectedLanguage = "en"
    // Provider
    @AppStorage("providerOverrides") var providerOverrides = ""

    // Indicator mode
    @AppStorage("indicatorMode") var indicatorModeRaw = IndicatorMode.floating.rawValue
    var indicatorMode: IndicatorMode {
        get { IndicatorMode(rawValue: indicatorModeRaw) ?? .floating }
        set { indicatorModeRaw = newValue.rawValue }
    }

    // Notch expansion style
    @AppStorage("notchExpansionStyle") var notchExpansionStyleRaw = NotchExpansionStyle.down.rawValue
    var notchExpansionStyle: NotchExpansionStyle {
        get { NotchExpansionStyle(rawValue: notchExpansionStyleRaw) ?? .down }
        set { notchExpansionStyleRaw = newValue.rawValue }
    }

    // Notch glow color (decoupled from themes)
    @AppStorage("notchGlowColorHex") var notchGlowColorHex = "#ffffff"
    var notchGlowColor: Color {
        get { Color(hex: notchGlowColorHex) }
        set { notchGlowColorHex = newValue.toHex() }
    }

    // Notch animation speed
    @AppStorage("notchAnimationSpeed") var notchAnimationSpeedRaw = NotchAnimationSpeed.normal.rawValue
    var notchAnimationSpeed: NotchAnimationSpeed {
        get { NotchAnimationSpeed(rawValue: notchAnimationSpeedRaw) ?? .normal }
        set { notchAnimationSpeedRaw = newValue.rawValue }
    }

    // Theme
    @AppStorage("indicatorThemeName") var indicatorThemeName = "system"

    // Visualization
    @AppStorage("waveformStyle") var waveformStyleRaw = WaveformStyle.classicBars.rawValue
    @AppStorage("indicatorScale") var indicatorScale = 0.5

    var waveformStyle: WaveformStyle {
        WaveformStyle(rawValue: waveformStyleRaw) ?? .classicBars
    }

    // Hold to Record
    @AppStorage("holdToRecordEnabled") var holdToRecordEnabled = false
    @AppStorage("holdToRecordKeyCode") var holdToRecordKeyCode = 0x0A // § key (kVK_ISO_Section)
    @AppStorage("holdToRecordKeyName") var holdToRecordKeyName = "§"
    @Published var holdToRecordTapActive = false

    // Real-time transcription (beta)
    @AppStorage("realtimeTranscriptionEnabled") var realtimeTranscriptionEnabled = false

    var isRealtimeActive: Bool {
        realtimeTranscriptionEnabled && selectedProviderID == .fluidAudio
    }

    var selectedProviderID: ASRProviderID {
        preferredProvider(for: selectedLanguage)
    }

    /// Returns the user's preferred provider for a language, or the catalog recommendation.
    func preferredProvider(for language: String) -> ASRProviderID {
        if let overrides = parseProviderOverrides(), let override = overrides[language] {
            return override
        }
        return ProviderCatalog.recommendedProvider(for: language)
    }

    /// Stores a per-language provider override (only if different from catalog default).
    func setPreferredProvider(_ provider: ASRProviderID, for language: String) {
        var overrides = parseProviderOverrides() ?? [:]
        if provider == ProviderCatalog.recommendedProvider(for: language) {
            overrides.removeValue(forKey: language)
        } else {
            overrides[language] = provider
        }
        if overrides.isEmpty {
            providerOverrides = ""
        } else {
            let dict = overrides.mapValues { $0.rawValue }
            if let data = try? JSONEncoder().encode(dict), let str = String(data: data, encoding: .utf8) {
                providerOverrides = str
            }
        }
    }

    private func parseProviderOverrides() -> [String: ASRProviderID]? {
        guard !providerOverrides.isEmpty,
              let data = providerOverrides.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return dict.compactMapValues { ASRProviderID(rawValue: $0) }
    }

    func currentIndicatorTheme(isDarkMode: Bool, customThemes: [IndicatorTheme] = []) -> IndicatorTheme {
        IndicatorTheme.resolve(id: indicatorThemeName, isDarkMode: isDarkMode, customThemes: customThemes)
    }

    func migrateModelNameIfNeeded() {
        let knownNames = Set(ModelManager.defaultModels.map(\.name))
        if !knownNames.contains(selectedModelName) {
            selectedModelName = "openai_whisper-tiny.en"
        }
    }

}
