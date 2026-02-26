import SwiftUI
import UniformTypeIdentifiers

struct SpeechRecognitionSettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var dictationSession: DictationSession
    @EnvironmentObject var vocabularyStore: VocabularyStore

    @State private var newMisrecognized = ""
    @State private var newCorrected = ""

    private var selectedLanguage: String { settingsStore.selectedLanguage }
    private var hasMultipleProviders: Bool { ProviderCatalog.hasMultipleProviders(for: selectedLanguage) }
    private var activeProvider: ASRProviderID { settingsStore.preferredProvider(for: selectedLanguage) }

    var body: some View {
        ScrollView {
            Form {
                languageSection
                if hasMultipleProviders {
                    providerSection
                }
                if activeProvider == .whisperKit {
                    whisperKitModelSection
                } else {
                    parakeetModelSection
                }
                automaticCorrectionsSection
                aiCleanupSection
                customVocabularySection
                silenceSection
                realtimeSection
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Text("Dictation language for speech recognition.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LanguagePicker(
                selectedLanguage: settingsStore.selectedLanguage,
                onSelect: { language in
                    dictationSession.switchLanguage(to: language.code)
                }
            )
            .disabled(dictationSession.state != .idle)
        } header: {
            SettingsSectionHeader(icon: "globe", title: "Language", color: .blue)
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        Section {
            let recommended = ProviderCatalog.recommendedProvider(for: selectedLanguage)
            let providers = ProviderCatalog.providers(for: selectedLanguage)

            Text("Multiple speech engines are available for this language.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(providers, id: \.self) { providerID in
                ProviderRow(
                    providerID: providerID,
                    isSelected: activeProvider == providerID,
                    isRecommended: providerID == recommended,
                    isDisabled: dictationSession.state != .idle,
                    onSelect: {
                        settingsStore.setPreferredProvider(providerID, for: selectedLanguage)
                        dictationSession.switchProvider(to: providerID)
                    }
                )
            }
        } header: {
            SettingsSectionHeader(icon: "cpu", title: "Speech Engine", color: .purple)
        }
    }

    // MARK: - WhisperKit Model

    private var whisperKitModelSection: some View {
        Section {
            Text("Models run locally on your Mac. Larger models are more accurate but slower. The listed size is loaded into RAM, so ensure you have enough free memory.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if settingsStore.selectedLanguage == "en" {
                InfoBanner(.info, "Tiny is recommended for English — it's fast and highly accurate. For other languages, switch the language above and use Medium or larger.")
            } else {
                let languageName = SupportedLanguage.all.first(where: { $0.code == settingsStore.selectedLanguage })?.name ?? settingsStore.selectedLanguage
                InfoBanner(.info, "For best results in \(languageName), use Medium or larger. Smaller models may produce inaccurate transcriptions for non-English languages.")
            }

            let isNonEnglish = settingsStore.selectedLanguage != "en"
            let filteredModels = modelManager.models(for: settingsStore.selectedLanguage)
            ForEach(filteredModels) { model in
                ModelRow(
                    model: model,
                    isSelected: settingsStore.selectedModelName == model.name,
                    isRecommended: isNonEnglish ? model.tier == .medium : model.tier == .tiny,
                    onSelect: {
                        dictationSession.switchModel(to: model.name)
                    },
                    onDownload: {
                        modelManager.downloadModel(model)
                    },
                    onCancel: {
                        modelManager.cancelDownload(model)
                    },
                    onDelete: {
                        modelManager.deleteModel(model)
                    }
                )
            }
        } header: {
            SettingsSectionHeader(icon: "arrow.down.circle", title: "Model", color: .green)
        }
    }

    // MARK: - Parakeet Model

    private var parakeetModelSection: some View {
        Section {
            Text("Parakeet runs locally on your Mac with a single model that supports 25 European languages.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(FluidAudioModelManager.displayName)
                            .fontWeight(fluidAudioModelManager.isDownloaded ? .semibold : .regular)
                        if fluidAudioModelManager.isDownloaded {
                            Text("Ready")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 8) {
                        Text(FluidAudioModelManager.size)
                        Text(FluidAudioModelManager.speed)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if fluidAudioModelManager.isDownloading {
                    HStack(spacing: 8) {
                        ProgressView(value: fluidAudioModelManager.downloadProgress, total: 1.0)
                            .frame(width: 100)
                        Text("\(Int(fluidAudioModelManager.downloadProgress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                        Button {
                            fluidAudioModelManager.cancelDownload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                } else if let error = fluidAudioModelManager.downloadError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("Download failed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(error)
                        Button("Retry") {
                            fluidAudioModelManager.downloadModel()
                        }
                        .buttonStyle(.borderless)
                    }
                } else if fluidAudioModelManager.isDownloaded {
                    Button(role: .destructive) {
                        fluidAudioModelManager.deleteModel()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(dictationSession.state != .idle)
                } else {
                    Button("Download") {
                        fluidAudioModelManager.downloadModel()
                    }
                    .disabled(dictationSession.state != .idle)
                }
            }
            .padding(.vertical, 4)
        } header: {
            SettingsSectionHeader(icon: "arrow.down.circle", title: "Parakeet Model", color: .green)
        }
    }

    // MARK: - Automatic Corrections

    private var automaticCorrectionsSection: some View {
        Section {
            Toggle("Remove filler words (um, uh, etc.)", isOn: $settingsStore.removeFillerWords)
            Toggle("Auto-capitalize sentences", isOn: $settingsStore.autoCapitalize)
            Toggle("Smart punctuation", isOn: $settingsStore.autoPunctuation)
        } header: {
            SettingsSectionHeader(icon: "textformat.abc", title: "Automatic Corrections", color: .blue)
        }
    }

    // MARK: - AI Cleanup

    private var aiCleanupSection: some View {
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
    }

    // MARK: - Custom Vocabulary

    private var customVocabularySection: some View {
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

    // MARK: - Vocabulary Import/Export

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

    // MARK: - Real-Time Transcription

    private var realtimeSection: some View {
        Section {
            if activeProvider == .fluidAudio {
                Text("Words appear live in the active app as you speak. Only available with the Parakeet engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable real-time transcription", isOn: $settingsStore.realtimeTranscriptionEnabled)
            } else {
                Text("Switch to Parakeet to enable real-time transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 6) {
                SettingsSectionHeader(icon: "bolt.fill", title: "Real-Time Transcription", color: .yellow)
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.15))
                    .cornerRadius(3)
            }
        }
    }

    // MARK: - Silence Detection

    private var silenceSection: some View {
        Section {
            Text("Will stop and paste the text into the selected input after this many seconds of silence.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Silence timeout:")
                Slider(value: $settingsStore.silenceTimeoutSeconds, in: 5...20, step: 1)
                Text("\(Int(settingsStore.silenceTimeoutSeconds))s")
                    .monospacedDigit()
                    .frame(width: 30)
            }
        } header: {
            SettingsSectionHeader(icon: "waveform.slash", title: "Silence Detection", color: .orange)
        }
    }
}

// MARK: - Provider Row

private struct ProviderRow: View {
    let providerID: ASRProviderID
    let isSelected: Bool
    let isRecommended: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    private var displayName: String {
        switch providerID {
        case .whisperKit: return "WhisperKit"
        case .fluidAudio: return "Parakeet"
        }
    }

    private var description: String {
        switch providerID {
        case .whisperKit: return "OpenAI Whisper models, multiple sizes"
        case .fluidAudio: return "NVIDIA Parakeet, ~190ms"
        }
    }

    private var supportedLanguages: [(flag: String, name: String)]? {
        guard providerID == .fluidAudio else { return nil }
        return ProviderCatalog.parakeetLanguages.compactMap { code in
            guard let lang = SupportedLanguage.all.first(where: { $0.code == code }) else { return nil }
            return (flag: lang.flag, name: lang.name)
        }
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .fontWeight(isSelected ? .semibold : .regular)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let languages = supportedLanguages {
                        Text(languages.map { "\($0.flag) \($0.name)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Language Picker

private struct LanguagePicker: View {
    let selectedLanguage: String
    let onSelect: (SupportedLanguage) -> Void

    @State private var showingPopover = false
    @State private var searchText = ""

    private var currentLanguage: SupportedLanguage {
        SupportedLanguage.all.first(where: { $0.code == selectedLanguage })
            ?? SupportedLanguage(code: "en", name: "English", flag: "🇬🇧")
    }

    private var filteredLanguages: [SupportedLanguage] {
        if searchText.isEmpty {
            return SupportedLanguage.all
        }
        return SupportedLanguage.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            HStack {
                Text(currentLanguage.flag)
                Text(currentLanguage.name)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.background)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search languages...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredLanguages) { language in
                            Button {
                                onSelect(language)
                                showingPopover = false
                                searchText = ""
                            } label: {
                                HStack {
                                    Text(language.flag)
                                    Text(language.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if language.code == selectedLanguage {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 300)
            }
            .frame(width: 280)
        }
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let isRecommended: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if isSelected && model.isDownloaded {
                        Text("Selected")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15))
                            .cornerRadius(4)
                    }
                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text(model.size)
                    Text(model.speed)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isDownloading {
                HStack(spacing: 8) {
                    ProgressView(value: model.downloadProgress, total: 1.0)
                        .frame(width: 100)
                    Text("\(Int(model.downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } else if let error = model.downloadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Download failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(error)
                    Button("Retry") { onDownload() }
                        .buttonStyle(.borderless)
                }
            } else if model.isDownloaded {
                HStack(spacing: 8) {
                    if !isSelected {
                        Button("Select") { onSelect() }
                            .buttonStyle(.borderless)
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Button("Download") { onDownload() }
            }
        }
        .padding(.vertical, 4)
    }
}
