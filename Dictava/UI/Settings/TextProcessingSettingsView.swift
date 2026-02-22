import SwiftUI
import UniformTypeIdentifiers

struct TextProcessingSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var vocabularyStore: VocabularyStore
    @State private var newMisrecognized = ""
    @State private var newCorrected = ""

    private let llmModels = [
        ("Llama 3.2 1B (Q4)", "~700 MB", "8 GB+ RAM"),
        ("Llama 3.2 3B (Q4)", "~2 GB", "16 GB+ RAM"),
        ("Qwen 3 8B (Q4)", "~5 GB", "32 GB+ RAM"),
    ]

    var body: some View {
        Form {
            Section("Automatic Corrections") {
                Toggle("Remove filler words (um, uh, etc.)", isOn: $settingsStore.removeFillerWords)
                Toggle("Auto-capitalize sentences", isOn: $settingsStore.autoCapitalize)
                Toggle("Smart punctuation", isOn: $settingsStore.autoPunctuation)
            }

            Section {
                Toggle("Enable AI text cleanup", isOn: $settingsStore.llmEnabled)

                Text("Uses a local LLM to fix grammar, adjust tone, or shorten text. Triggered by voice commands like \"fix grammar\" or \"make it formal\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settingsStore.llmEnabled {
                    Text("Coming in a future update")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.quaternary)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planned Models")
                            .font(.subheadline.bold())

                        ForEach(llmModels, id: \.0) { model in
                            HStack {
                                Text(model.0)
                                Spacer()
                                Text(model.1)
                                    .foregroundStyle(.secondary)
                                Text(model.2)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                Text("AI Cleanup")
            }

            Section {
                Text("Fix words that Whisper consistently misrecognizes. The misrecognized form will be automatically replaced with the correct form.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                    Text("No custom vocabulary entries yet. Add words that Whisper frequently gets wrong.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
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
                    Text("Custom Vocabulary")
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
