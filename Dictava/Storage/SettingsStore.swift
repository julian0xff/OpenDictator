import SwiftUI
import Combine

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
    @AppStorage("disabledVoiceCommands") var disabledVoiceCommands = ""

    // Provider
    @AppStorage("providerOverrides") var providerOverrides = ""

    // Theme
    @AppStorage("indicatorThemeName") var indicatorThemeName = "system"

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

    func isVoiceCommandEnabled(_ name: String) -> Bool {
        !disabledVoiceCommands.split(separator: ",").contains(Substring(name))
    }

    func setVoiceCommandEnabled(_ name: String, enabled: Bool) {
        var set = Set(disabledVoiceCommands.split(separator: ",").map(String.init))
        if enabled {
            set.remove(name)
        } else {
            set.insert(name)
        }
        disabledVoiceCommands = set.joined(separator: ",")
    }
}
