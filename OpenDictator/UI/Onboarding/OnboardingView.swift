import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    let settingsStore: SettingsStore
    @ObservedObject var modelManager: ModelManager
    @State private var currentStep = 0
    @State private var downloadingModelID: String?
    @Environment(\.dismiss) var dismiss

    private let steps = ["Welcome", "Microphone", "Accessibility", "Model", "Ready"]
    private let theme: SettingsTheme = .warm

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
                } else {
                    Button("Get Started") {
                        settingsStore.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .background(theme.windowBackground)
        .environment(\.settingsTheme, theme)
    }

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

            let status = PermissionManager.shared.microphoneStatus
            PermissionStatusBadge(status: status, theme: theme)

            if status != .granted {
                Button("Grant Microphone Access") {
                    Task { await PermissionManager.shared.requestMicrophone() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

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

            let status = PermissionManager.shared.accessibilityStatus
            PermissionStatusBadge(status: status, theme: theme)

            if status != .granted {
                Button("Open Accessibility Settings") {
                    PermissionManager.shared.requestAccessibility()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var downloadingModel: WhisperModel? {
        guard let id = downloadingModelID else { return nil }
        return modelManager.availableModels.first(where: { $0.id == id })
    }

    private var modelStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(theme.controlAccent)

            Text("Download a Model")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)

            Text("Choose a Whisper model. Tiny is recommended to start — it's fast and works great for English dictation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            if let tracked = downloadingModel {
                if tracked.isDownloading {
                    VStack {
                        ProgressView(value: tracked.downloadProgress) {
                            Text("Downloading model...")
                                .foregroundStyle(theme.textSecondary)
                        }
                        .tint(theme.controlAccent)
                        Text("\(Int(tracked.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                } else if let error = tracked.downloadError {
                    VStack(spacing: 8) {
                        Text("Download failed: \(error)")
                            .foregroundStyle(theme.destructive)
                            .font(.caption)
                        Button("Retry") {
                            modelManager.downloadModel(tracked)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                } else if tracked.isDownloaded {
                    Label("Model downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                        .onAppear {
                            settingsStore.selectedModelName = tracked.name
                        }
                }
            } else {
                ForEach(modelManager.availableModels.prefix(2)) { model in
                    Button {
                        downloadModel(model)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                    .fontWeight(.medium)
                                    .foregroundStyle(theme.textPrimary)
                                Text("\(model.size) \u{2022} \(model.speed)")
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            if model.isDownloaded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.success)
                            }
                        }
                        .padding()
                        .background(theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: SettingsTheme.radiusSm)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(theme.success)

            Text("You're All Set!")
                .font(.largeTitle.bold())
                .foregroundStyle(theme.textPrimary)

            Text("Press Option+Space to start dictating. Text will appear wherever your cursor is.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            KeyboardShortcuts.Recorder("Customize hotkey:", name: .toggleDictation)
                .padding(.top)

            Text("You can change settings anytime from the menu bar icon.")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func downloadModel(_ model: WhisperModel) {
        downloadingModelID = model.id
        modelManager.downloadModel(model)
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
