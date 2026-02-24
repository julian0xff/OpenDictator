import SwiftUI
import UniformTypeIdentifiers

struct TextProcessingSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var vocabularyStore: VocabularyStore
    @State private var newMisrecognized = ""
    @State private var newCorrected = ""

    var body: some View {
        ScrollView {
        Form {
            Section {
                Toggle("Remove filler words (um, uh, etc.)", isOn: $settingsStore.removeFillerWords)
                Toggle("Auto-capitalize sentences", isOn: $settingsStore.autoCapitalize)
                Toggle("Smart punctuation", isOn: $settingsStore.autoPunctuation)
            } header: {
                SettingsSectionHeader(icon: "textformat.abc", title: "Automatic Corrections", color: .blue)
            }

            Section {
                HStack {
                    Toggle("Enable AI text cleanup", isOn: $settingsStore.llmEnabled)
                        .disabled(true)
                    Text("Coming Soon")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.secondary))
                }

                InfoBanner(.tip, "AI cleanup will use a local LLM to fix grammar, adjust tone, or shorten text via voice commands like \"fix grammar\" or \"make it formal.\"")
            } header: {
                SettingsSectionHeader(icon: "sparkles", title: "AI Cleanup", color: .purple)
            }

            Section {
                HStack {
                    TextField("Misrecognized", text: $newMisrecognized)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("Correct", text: $newCorrected)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newMisrecognized.isEmpty, !newCorrected.isEmpty else { return }
                        vocabularyStore.addEntry(VocabularyEntry(
                            misrecognized: newMisrecognized,
                            corrected: newCorrected
                        ))
                        newMisrecognized = ""
                        newCorrected = ""
                    }
                    .disabled(newMisrecognized.isEmpty || newCorrected.isEmpty)
                }

                if vocabularyStore.entries.isEmpty {
                    EmptyStateView(
                        icon: "character.book.closed",
                        title: "No custom vocabulary",
                        message: "Add words that Whisper frequently misrecognizes to automatically correct them."
                    )
                }

                ForEach(vocabularyStore.entries) { entry in
                    HStack {
                        Text(entry.misrecognized)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(entry.corrected)
                            .fontWeight(.medium)
                    }
                }
                .onDelete { offsets in
                    vocabularyStore.removeEntry(at: offsets)
                }
            } header: {
                HStack {
                    SettingsSectionHeader(icon: "character.book.closed", title: "Custom Vocabulary", color: .orange)
                    Spacer()
                    Button("Import") { importVocabulary() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    Button("Export") { exportVocabulary() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        }
    }

    private func exportVocabulary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vocabulary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(vocabularyStore.entries) else { return }
        try? data.write(to: url)
    }

    private func importVocabulary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode([VocabularyEntry].self, from: data) else { return }

        let existingPairs = Set(vocabularyStore.entries.map { "\($0.misrecognized)|\($0.corrected)" })
        for entry in imported {
            let key = "\(entry.misrecognized)|\(entry.corrected)"
            if !existingPairs.contains(key) {
                vocabularyStore.addEntry(VocabularyEntry(misrecognized: entry.misrecognized, corrected: entry.corrected))
            }
        }
    }
}
