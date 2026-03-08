import SwiftUI
import UniformTypeIdentifiers

struct SpeechRecognitionSettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var dictationSession: DictationSession
    @EnvironmentObject var vocabularyStore: VocabularyStore
    @Environment(\.settingsTheme) private var theme

    @State private var newMisrecognized = ""
    @State private var newCorrected = ""

    private var selectedLanguage: String { settingsStore.selectedLanguage }
    private var hasMultipleProviders: Bool { ProviderCatalog.hasMultipleProviders(for: selectedLanguage) }
    private var activeProvider: ASRProviderID { settingsStore.preferredProvider(for: selectedLanguage) }

    var body: some View {
        ScrollView {
            VStack(spacing: SettingsTheme.spacing16) {
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
            .padding(SettingsTheme.spacing20)
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        SettingsCard(title: "Language", subtitle: "Dictation language for speech recognition.") {
            LanguagePicker(
                selectedLanguage: settingsStore.selectedLanguage,
                onSelect: { language in
                    dictationSession.switchLanguage(to: language.code)
                }
            )
            .disabled(dictationSession.state != .idle)
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        SettingsCard(title: "Speech Engine", subtitle: "Multiple speech engines are available for this language.") {
            let recommended = ProviderCatalog.recommendedProvider(for: selectedLanguage)
            let providers = ProviderCatalog.providers(for: selectedLanguage)

            VStack(spacing: SettingsTheme.spacing8) {
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
            }
        }
    }

    // MARK: - WhisperKit Model

    private var whisperKitModelSection: some View {
        SettingsCard(title: "Model", subtitle: "Models run locally on your Mac. Larger models are more accurate but slower.") {
            VStack(alignment: .leading, spacing: SettingsTheme.spacing12) {
                if settingsStore.selectedLanguage == "en" {
                    InfoBanner(.info, "Tiny is recommended for English \u{2014} it's fast and highly accurate. For other languages, switch the language above and use Medium or larger.")
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

                    if model.id != filteredModels.last?.id {
                        Divider()
                            .background(theme.border)
                    }
                }
            }
        }
    }

    // MARK: - Parakeet Model

    private var parakeetModelSection: some View {
        SettingsCard(title: "Parakeet Model", subtitle: "Parakeet runs locally on your Mac with a single model that supports 25 European languages.") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(FluidAudioModelManager.displayName)
                            .fontWeight(fluidAudioModelManager.isDownloaded ? .semibold : .regular)
                            .foregroundStyle(theme.textPrimary)
                        if fluidAudioModelManager.isDownloaded {
                            Text("Ready")
                                .font(.caption2)
                                .foregroundStyle(theme.success)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.successBackground)
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 8) {
                        Text(FluidAudioModelManager.size)
                        Text(FluidAudioModelManager.speed)
                    }
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                if fluidAudioModelManager.isDownloading {
                    HStack(spacing: 8) {
                        ProgressView(value: fluidAudioModelManager.downloadProgress, total: 1.0)
                            .frame(width: 100)
                        Text("\(Int(fluidAudioModelManager.downloadProgress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                        Button {
                            fluidAudioModelManager.cancelDownload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.textSecondary)
                        }
                        .buttonStyle(.borderless)
                    }
                } else if let error = fluidAudioModelManager.downloadError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.warning)
                            .font(.caption)
                        Text("Download failed")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .help(error)
                        Button("Retry") {
                            fluidAudioModelManager.downloadModel()
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                } else if fluidAudioModelManager.isDownloaded {
                    Button(role: .destructive) {
                        fluidAudioModelManager.deleteModel()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(theme.destructive)
                    }
                    .buttonStyle(.borderless)
                    .disabled(dictationSession.state != .idle)
                } else {
                    Button("Download") {
                        fluidAudioModelManager.downloadModel()
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(dictationSession.state != .idle)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Automatic Corrections

    private var automaticCorrectionsSection: some View {
        SettingsCard(title: "Automatic Corrections") {
            VStack(spacing: SettingsTheme.spacing12) {
                Toggle("Remove filler words (um, uh, etc.)", isOn: $settingsStore.removeFillerWords)
                Toggle("Auto-capitalize sentences", isOn: $settingsStore.autoCapitalize)
                Toggle("Smart punctuation", isOn: $settingsStore.autoPunctuation)
            }
        }
    }

    // MARK: - AI Cleanup

    private var aiCleanupSection: some View {
        SettingsCard(title: "AI Cleanup") {
            VStack(alignment: .leading, spacing: SettingsTheme.spacing12) {
                Toggle(isOn: $settingsStore.llmEnabled) {
                    HStack(spacing: 6) {
                        Text("Enable AI text cleanup")
                        Text("Coming Soon")
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.controlBackground)
                            .clipShape(Capsule())
                    }
                }
                .disabled(true)

                InfoBanner(.tip, "AI cleanup will use a local LLM to fix grammar, adjust tone, or shorten text via voice commands like \"fix grammar\" or \"make it formal.\"")
            }
        }
    }

    // MARK: - Custom Vocabulary

    private var customVocabularySection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsTheme.spacing12) {
                HStack {
                    Text("Custom Vocabulary")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button("Import") { importVocabulary() }
                        .buttonStyle(GhostButtonStyle())
                        .font(.caption)
                    Button("Export") { exportVocabulary() }
                        .buttonStyle(GhostButtonStyle())
                        .font(.caption)
                }

                HStack {
                    TextField("Misrecognized", text: $newMisrecognized)
                        .shadcnTextField()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(theme.textTertiary)
                    TextField("Correct", text: $newCorrected)
                        .shadcnTextField()
                    Button("Add") {
                        guard !newMisrecognized.isEmpty, !newCorrected.isEmpty else { return }
                        vocabularyStore.addEntry(VocabularyEntry(
                            misrecognized: newMisrecognized,
                            corrected: newCorrected
                        ))
                        newMisrecognized = ""
                        newCorrected = ""
                    }
                    .buttonStyle(GhostButtonStyle())
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
                            .foregroundStyle(theme.textSecondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary)
                        Text(entry.corrected)
                            .fontWeight(.medium)
                            .foregroundStyle(theme.textPrimary)
                    }
                }
                .onDelete { offsets in
                    vocabularyStore.removeEntry(at: offsets)
                }
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
        SettingsCard {
            VStack(alignment: .leading, spacing: SettingsTheme.spacing12) {
                HStack(spacing: 6) {
                    Text("Real-Time Transcription")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.textPrimary)
                    Text("BETA")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.warningBackground)
                        .cornerRadius(3)
                }

                if activeProvider == .fluidAudio {
                    Text("Words appear live in the active app as you speak. Only available with the Parakeet engine.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)

                    Toggle("Enable real-time transcription", isOn: $settingsStore.realtimeTranscriptionEnabled)
                } else {
                    Text("Switch to Parakeet to enable real-time transcription.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Silence Detection

    private var silenceSection: some View {
        SettingsCard(title: "Silence Detection", subtitle: "Will stop and paste the text into the selected input after this many seconds of silence.") {
            HStack {
                Text("Silence timeout:")
                    .foregroundStyle(theme.textPrimary)
                Slider(value: $settingsStore.silenceTimeoutSeconds, in: 5...20, step: 1)
                Text("\(Int(settingsStore.silenceTimeoutSeconds))s")
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 30)
            }
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
    @Environment(\.settingsTheme) private var theme

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
                    .foregroundStyle(isSelected ? theme.controlAccent : theme.textTertiary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(theme.textPrimary)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2)
                                .foregroundStyle(theme.controlAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.controlAccent.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    if let languages = supportedLanguages {
                        Text(languages.map { "\($0.flag) \($0.name)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
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
    @Environment(\.settingsTheme) private var theme

    @State private var showingPopover = false
    @State private var searchText = ""

    private var currentLanguage: SupportedLanguage {
        SupportedLanguage.all.first(where: { $0.code == selectedLanguage })
            ?? SupportedLanguage(code: "en", name: "English", flag: "\u{1f1ec}\u{1f1e7}")
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
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(theme.textTertiary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(theme.cardBackground)
            .cornerRadius(SettingsTheme.radiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.textTertiary)
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
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    if language.code == selectedLanguage {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(theme.controlAccent)
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
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(theme.textPrimary)
                    if isSelected && model.isDownloaded {
                        Text("Selected")
                            .font(.caption2)
                            .foregroundStyle(theme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.successBackground)
                            .cornerRadius(4)
                    }
                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .foregroundStyle(theme.controlAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.controlAccent.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text(model.size)
                    Text(model.speed)
                }
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            if model.isDownloading {
                HStack(spacing: 8) {
                    ProgressView(value: model.downloadProgress, total: 1.0)
                        .frame(width: 100)
                    Text("\(Int(model.downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 32, alignment: .trailing)
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            } else if let error = model.downloadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.warning)
                        .font(.caption)
                    Text("Download failed")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .help(error)
                    Button("Retry") { onDownload() }
                        .buttonStyle(GhostButtonStyle())
                }
            } else if model.isDownloaded {
                HStack(spacing: 8) {
                    if !isSelected {
                        Button("Select") { onSelect() }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(theme.destructive)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Button("Download") { onDownload() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}
