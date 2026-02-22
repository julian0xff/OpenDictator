import SwiftUI

struct VoiceCommandSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                Text("Say these phrases at the end of your dictation to trigger actions. Commands are detected after you stop speaking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(VoiceCommandParser.allDefinitions, id: \.name) { definition in
                    let enabled = Binding(
                        get: { settingsStore.isVoiceCommandEnabled(definition.name) },
                        set: { settingsStore.setVoiceCommandEnabled(definition.name, enabled: $0) }
                    )

                    Toggle(isOn: enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.name.replacingOccurrences(of: "llmRewrite.", with: ""))
                                .fontWeight(.medium)
                            Text(definition.triggers.map { "\"\($0)\"" }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Voice Commands")
            }
        }
        .formStyle(.grouped)
    }
}
