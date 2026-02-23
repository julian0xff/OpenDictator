import SwiftUI

struct SpeechRecognitionSettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var dictationSession: DictationSession

    var body: some View {
        ScrollView {
            Form {
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
                } header: {
                    Text("Language")
                }

                Section {
                    Text("Models run locally on your Mac. Larger models are more accurate but slower. The listed size is loaded into RAM, so ensure you have enough free memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settingsStore.selectedLanguage == "en" {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Tiny is recommended for English — it's fast and highly accurate. For other languages, switch the language above and use Medium or larger.")
                                .font(.caption)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.08))
                        .cornerRadius(8)
                    } else {
                        let languageName = SupportedLanguage.all.first(where: { $0.code == settingsStore.selectedLanguage })?.name ?? settingsStore.selectedLanguage
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("For best results in \(languageName), use Medium or larger. Smaller models may produce inaccurate transcriptions for non-English languages.")
                                .font(.caption)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.08))
                        .cornerRadius(8)
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
                    Text("Model")
                }

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
                    Text("Silence Detection")
                }
            }
            .formStyle(.grouped)
        }
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
