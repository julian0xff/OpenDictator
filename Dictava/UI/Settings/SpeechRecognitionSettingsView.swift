import SwiftUI

struct SpeechRecognitionSettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var dictationSession: DictationSession

    var body: some View {
        Form {
            Section {
                Text("Models run locally on your Mac using CoreML. Larger models are more accurate but slower.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(modelManager.availableModels) { model in
                    ModelRow(
                        model: model,
                        isSelected: settingsStore.selectedModelName == model.name,
                        onSelect: {
                            dictationSession.switchModel(to: model.name)
                        },
                        onDownload: {
                            Task {
                                try? await modelManager.downloadModel(model)
                            }
                        },
                        onDelete: {
                            modelManager.deleteModel(model)
                        }
                    )
                }
            } header: {
                Text("Whisper Model")
            }

            Section {
                Text("Will stop and paste the text into the selected input after this many seconds of silence. Gives you time to pause and think without cutting you off.")
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

struct ModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if isSelected && model.isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                    if model.name.contains("tiny.en") {
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
                    Text("~\(model.speed)")
                    Text(model.description)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
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
