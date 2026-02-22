import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("selectedModelName") var selectedModelName = "tiny.en"
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
    @AppStorage("disabledVoiceCommands") var disabledVoiceCommands = ""

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
