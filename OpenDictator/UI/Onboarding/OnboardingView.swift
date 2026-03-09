import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    let settingsStore: SettingsStore
    @ObservedObject var modelManager: ModelManager
    @State private var currentStep = 0
    @State private var downloadingModelID: String?
    @Environment(\.dismiss) var dismiss

    private let steps = ["Welcome", "Microphone", "Accessibility", "Model", "Ready"]

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
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
                }
                Spacer()
                if currentStep < steps.count - 1 {
                    Button("Continue") { withAnimation(.easeInOut(duration: 0.25)) { currentStep += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        settingsStore.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to OpenDictator")
                .font(.largeTitle.bold())

            Text("Free, open-source voice dictation that runs entirely on your Mac. No internet, no subscriptions, no data leaves your device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "mic.fill", text: "Press a hotkey and speak")
                FeatureRow(icon: "text.cursor", text: "Text appears at your cursor in any app")
                FeatureRow(icon: "lock.shield", text: "100% local, 100% private")
                FeatureRow(icon: "bolt.fill", text: "Powered by WhisperKit & Parakeet on Apple Silicon")
            }
            .padding(.top)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Microphone Access")
                .font(.title2.bold())

            Text("OpenDictator needs microphone access to hear your voice. Audio is processed locally and never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            let status = PermissionManager.shared.microphoneStatus
            PermissionStatusBadge(status: status)

            if status != .granted {
                Button("Grant Microphone Access") {
                    Task { await PermissionManager.shared.requestMicrophone() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Accessibility Access")
                .font(.title2.bold())

            Text("OpenDictator needs accessibility access to type text into other apps. This allows the hotkey and text injection to work system-wide.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            let status = PermissionManager.shared.accessibilityStatus
            PermissionStatusBadge(status: status)

            if status != .granted {
                Button("Open Accessibility Settings") {
                    PermissionManager.shared.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
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
                .foregroundStyle(.green)

            Text("Download a Model")
                .font(.title2.bold())

            Text("Choose a Whisper model. Tiny is recommended to start — it's fast and works great for English dictation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let tracked = downloadingModel {
                if tracked.isDownloading {
                    VStack {
                        ProgressView(value: tracked.downloadProgress) {
                            Text("Downloading model...")
                        }
                        Text("\(Int(tracked.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = tracked.downloadError {
                    VStack(spacing: 8) {
                        Text("Download failed: \(error)")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Button("Retry") {
                            modelManager.downloadModel(tracked)
                        }
                    }
                } else if tracked.isDownloaded {
                    Label("Model downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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
                                Text("\(model.size) • \(model.speed)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.isDownloaded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .background(.quaternary)
                        .cornerRadius(8)
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
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle.bold())

            Text("Press Option+Space to start dictating. Text will appear wherever your cursor is.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            KeyboardShortcuts.Recorder("Customize hotkey:", name: .toggleDictation)
                .padding(.top)

            Text("You can change settings anytime from the menu bar icon.")
                .font(.caption)
                .foregroundStyle(.tertiary)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            Text(text)
        }
    }
}

struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        HStack {
            switch status {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Not Granted", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .notDetermined:
                Label("Not Yet Requested", systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
    }
}
