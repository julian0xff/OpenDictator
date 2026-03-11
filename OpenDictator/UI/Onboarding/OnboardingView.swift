import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    let settingsStore: SettingsStore
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var currentStep = 0
    @State private var selectedProvider: ASRProviderID?
    @State private var downloadingWhisperModelID: String?
    @Environment(\.dismiss) var dismiss

    private let steps = ["Welcome", "Microphone", "Accessibility", "Model", "Ready"]
    private let theme: SettingsTheme = .warm

    // MARK: - Helpers

    private var tinyWhisperModel: WhisperModel? {
        modelManager.models(for: settingsStore.selectedLanguage).first(where: { $0.tier == .tiny })
    }

    private var isModelReady: Bool {
        switch selectedProvider {
        case .fluidAudio: return fluidAudioModelManager.isDownloaded
        case .whisperKit: return tinyWhisperModel?.isDownloaded == true
        case .none: return false
        }
    }

    private var downloadingWhisperModel: WhisperModel? {
        guard let id = downloadingWhisperModelID else { return nil }
        return modelManager.availableModels.first(where: { $0.id == id })
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= currentStep ? theme.controlAccent : theme.controlBackground)
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.25), value: currentStep)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // Content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: microphoneStep
                case 2: accessibilityStep
                case 3: modelStep
                case 4: readyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(currentStep)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: currentStep)
            .padding(32)

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") { withAnimation(.easeInOut(duration: 0.25)) { currentStep -= 1 } }
                        .buttonStyle(GhostButtonStyle())
                }
                Spacer()
                if currentStep < steps.count - 1 {
                    Button("Continue") { withAnimation(.easeInOut(duration: 0.25)) { currentStep += 1 } }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(currentStep == 3 && !isModelReady)
                } else {
                    Button("Open Settings") {
                        dismiss()
                        DispatchQueue.main.async {
                            NSApp.sendAction(#selector(AppDelegate.completeOnboarding), to: nil, from: nil)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissionManager.allPermissionsGranted || !isModelReady)
                }
            }
            .padding()
        }
        .background(theme.windowBackground)
        .environment(\.settingsTheme, theme)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(theme.controlAccent)

            Text("Welcome to OpenDictator")
                .font(.largeTitle.bold())
                .foregroundStyle(theme.textPrimary)

            Text("Free, open-source voice dictation that runs entirely on your Mac. No internet, no subscriptions, no data leaves your device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "mic.fill", text: "Press a hotkey and speak", theme: theme)
                FeatureRow(icon: "text.cursor", text: "Text appears at your cursor in any app", theme: theme)
                FeatureRow(icon: "lock.shield", text: "100% local, 100% private", theme: theme)
                FeatureRow(icon: "bolt.fill", text: "Powered by WhisperKit & Parakeet on Apple Silicon", theme: theme)
            }
            .padding(.top)
        }
    }

    // MARK: - Microphone

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(theme.controlAccent)

            Text("Microphone Access")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)

            Text("OpenDictator needs microphone access to hear your voice. Audio is processed locally and never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            let status = permissionManager.microphoneStatus
            PermissionStatusBadge(status: status, theme: theme)

            if status != .granted {
                Button("Grant Microphone Access") {
                    Task { await permissionManager.requestMicrophone() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(theme.success)

            Text("Accessibility Access")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)

            Text("OpenDictator needs accessibility access to type text into other apps. This allows the hotkey and text injection to work system-wide.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            let status = permissionManager.accessibilityStatus
            PermissionStatusBadge(status: status, theme: theme)

            if status != .granted {
                Button("Open Accessibility Settings") {
                    permissionManager.requestAccessibility()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Model Selection

    private var modelStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(theme.controlAccent)

            Text("Choose a Speech Engine")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)

            Text("Pick one to get started. You can switch or download more models later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            // Provider cards
            VStack(spacing: 8) {
                providerCard(
                    provider: .fluidAudio,
                    name: "Parakeet",
                    detail: "NVIDIA \u{2022} \(FluidAudioModelManager.size) \u{2022} \(FluidAudioModelManager.speed)",
                    isRecommended: true
                )

                if let tiny = tinyWhisperModel {
                    providerCard(
                        provider: .whisperKit,
                        name: "WhisperKit Tiny",
                        detail: "OpenAI Whisper \u{2022} \(tiny.size) \u{2022} \(tiny.speed)",
                        isRecommended: false
                    )
                }
            }

            // Download status
            downloadStatusView
        }
        .onAppear {
            if selectedProvider == nil {
                let preferred = settingsStore.preferredProvider(for: settingsStore.selectedLanguage)
                if preferred == .fluidAudio && fluidAudioModelManager.isDownloaded {
                    selectedProvider = .fluidAudio
                } else if preferred == .whisperKit, let model = tinyWhisperModel, model.isDownloaded {
                    selectedProvider = .whisperKit
                }
            }
        }
    }

    private func providerCard(provider: ASRProviderID, name: String, detail: String, isRecommended: Bool) -> some View {
        let isSelected = selectedProvider == provider

        return Button {
            selectProvider(provider)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? theme.controlAccent : theme.textTertiary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
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
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                if isModelDownloaded(for: provider) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                }
            }
            .padding()
            .background(isSelected ? theme.selectedBackground : theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusSm)
                    .stroke(isSelected ? theme.controlAccent : theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var downloadStatusView: some View {
        switch selectedProvider {
        case .fluidAudio:
            if fluidAudioModelManager.isDownloaded {
                Label("Model ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
            } else if fluidAudioModelManager.isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: fluidAudioModelManager.downloadProgress) {
                        Text("Downloading Parakeet...")
                            .foregroundStyle(theme.textSecondary)
                    }
                    .tint(theme.controlAccent)
                    Text("\(Int(fluidAudioModelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
            } else if let error = fluidAudioModelManager.downloadError {
                VStack(spacing: 8) {
                    Text("Download failed: \(error)")
                        .foregroundStyle(theme.destructive)
                        .font(.caption)
                    Button("Retry") { fluidAudioModelManager.downloadModel() }
                        .buttonStyle(GhostButtonStyle())
                }
            } else {
                EmptyView()
            }

        case .whisperKit:
            if let model = downloadingWhisperModel ?? tinyWhisperModel {
                if model.isDownloaded {
                    Label("Model ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                } else if model.isDownloading {
                    VStack(spacing: 4) {
                        ProgressView(value: model.downloadProgress) {
                            Text("Downloading WhisperKit Tiny...")
                                .foregroundStyle(theme.textSecondary)
                        }
                        .tint(theme.controlAccent)
                        Text("\(Int(model.downloadProgress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                    }
                } else if let error = model.downloadError {
                    VStack(spacing: 8) {
                        Text("Download failed: \(error)")
                            .foregroundStyle(theme.destructive)
                            .font(.caption)
                        Button("Retry") { modelManager.downloadModel(model) }
                            .buttonStyle(GhostButtonStyle())
                    }
                } else {
                    EmptyView()
                }
            }

        case .none:
            EmptyView()
        }
    }

    private func isModelDownloaded(for provider: ASRProviderID) -> Bool {
        switch provider {
        case .fluidAudio: return fluidAudioModelManager.isDownloaded
        case .whisperKit: return tinyWhisperModel?.isDownloaded == true
        }
    }

    private func selectProvider(_ provider: ASRProviderID) {
        // Cancel the other provider's download if switching
        if selectedProvider == .fluidAudio && provider != .fluidAudio && fluidAudioModelManager.isDownloading {
            fluidAudioModelManager.cancelDownload()
        }
        if selectedProvider == .whisperKit && provider != .whisperKit,
           let model = tinyWhisperModel, model.isDownloading {
            modelManager.cancelDownload(model)
        }

        selectedProvider = provider

        // Persist preference
        let lang = settingsStore.selectedLanguage
        settingsStore.setPreferredProvider(provider, for: lang)
        if provider == .whisperKit, let model = tinyWhisperModel {
            settingsStore.selectedModelName = model.name
        }

        // Auto-start download if needed
        switch provider {
        case .fluidAudio:
            if !fluidAudioModelManager.isDownloaded && !fluidAudioModelManager.isDownloading {
                fluidAudioModelManager.downloadModel()
            }
        case .whisperKit:
            if let model = tinyWhisperModel, !model.isDownloaded && !model.isDownloading {
                downloadingWhisperModelID = model.id
                modelManager.downloadModel(model)
            }
        }
    }

    // MARK: - Ready

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(theme.success)

            Text("You're All Set!")
                .font(.largeTitle.bold())
                .foregroundStyle(theme.textPrimary)

            Text("Open Settings to customize your hotkey, appearance, and more. Press Option+Space to start dictating anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            if !permissionManager.allPermissionsGranted {
                Label("Go back to grant required permissions before continuing.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(theme.warning)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    var theme: SettingsTheme = .warm

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(theme.controlAccent)
                .padding(4)
                .background(theme.controlAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(text)
                .foregroundStyle(theme.textPrimary)
        }
    }
}

struct PermissionStatusBadge: View {
    let status: PermissionStatus
    var theme: SettingsTheme = .warm

    var body: some View {
        HStack {
            switch status {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
            case .denied:
                Label("Not Granted", systemImage: "xmark.circle.fill")
                    .foregroundStyle(theme.destructive)
            case .notDetermined:
                Label("Not Yet Requested", systemImage: "questionmark.circle")
                    .foregroundStyle(theme.warning)
            }
        }
        .font(.callout)
    }
}
