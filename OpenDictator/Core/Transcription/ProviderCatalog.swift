import Foundation

struct ProviderCatalog {
    /// Languages supported by Parakeet v3 (25 European languages)
    static let parakeetLanguages: Set<String> = [
        "en", "es", "fr", "de", "it", "pt", "nl", "pl", "ro", "ru",
        "uk", "sv", "da", "fi", "el", "hu", "cs", "sk", "sl", "hr",
        "bg", "et", "lv", "lt", "mt"
    ]

    /// Returns available providers for a language, ordered by preference.
    /// Parakeet is recommended for all 25 supported languages.
    static func providers(for language: String) -> [ASRProviderID] {
        if parakeetLanguages.contains(language) {
            return [.fluidAudio, .whisperKit]
        }
        return [.whisperKit]
    }

    /// Returns the recommended provider for a language.
    static func recommendedProvider(for language: String) -> ASRProviderID {
        providers(for: language).first!
    }

    /// Whether a language has multiple provider options.
    static func hasMultipleProviders(for language: String) -> Bool {
        providers(for: language).count > 1
    }

    /// Whether a specific provider supports a language.
    static func isProviderSupported(_ provider: ASRProviderID, for language: String) -> Bool {
        switch provider {
        case .whisperKit: return true
        case .fluidAudio: return parakeetLanguages.contains(language)
        }
    }
}
