import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var dictationSession: DictationSession
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var transcriptionLogStore: TranscriptionLogStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DictavaTheme.spacing24) {
                header
                hotkeysSection
                behaviorSection
                modelsSection
                indicatorSection
                dataSection
                aboutSection
                quitButton
            }
            .padding(DictavaTheme.spacing24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .environment(\.theme, .ember)
        .toggleStyle(DictavaToggleStyle())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Dictava")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.caption)
                .foregroundStyle(theme.textMuted)
        }
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: DictavaTheme.spacing8) {
            sectionLabel("HOTKEYS")

            DictavaCard {
                VStack(spacing: DictavaTheme.spacing12) {
                    hotkeyRow("Toggle Dictation", name: .toggleDictation)
                    Divider().overlay(theme.border)
                    hotkeyRow("Copy Last", name: .copyLastTranscription)
                }
            }

            DictavaCard {
                VStack(spacing: DictavaTheme.spacing12) {
                    Toggle("Hold to Record", isOn: $settingsStore.holdToRecordEnabled)
                        .onChange(of: settingsStore.holdToRecordEnabled) { _, _ in
                            NSApp.sendAction(#selector(AppDelegate.updateHoldToRecord), to: nil, from: nil)
                        }

                    if settingsStore.holdToRecordEnabled {
                        HStack {
                            Text("Hold key")
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            HoldKeyRecorderButton(
                                keyName: $settingsStore.holdToRecordKeyName,
                                keyCode: $settingsStore.holdToRecordKeyCode
                            )
                        }
                        .transition(.opacity)

                        if !settingsStore.holdToRecordTapActive && PermissionManager.shared.accessibilityStatus != .granted {
                            HStack(spacing: DictavaTheme.spacing8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(theme.warning)
                                    .font(.caption)
                                Text("Accessibility permission required")
                                    .font(.caption)
                                    .foregroundStyle(theme.warning)
                            }
                        }
                    }
                }
            }
        }
    }

    private func hotkeyRow(_ label: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
                .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: DictavaTheme.spacing8) {
            sectionLabel("BEHAVIOR")

            DictavaCard {
                VStack(spacing: DictavaTheme.spacing12) {
                    Toggle("Play start/stop sounds", isOn: $settingsStore.playStartStopSounds)
                    Divider().overlay(theme.border)

                    // Indicator mode picker
                    HStack {
                        Text("Dictation indicator")
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(IndicatorMode.allCases) { mode in
                                let isActive = settingsStore.indicatorMode == mode

                                Button {
                                    settingsStore.indicatorMode = mode
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: mode.sfSymbol)
                                            .font(.system(size: 10))
                                        Text(mode.displayName)
                                            .font(.caption)
                                    }
                                    .foregroundStyle(isActive ? theme.textPrimary : theme.textMuted)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                                            .fill(isActive ? theme.surface : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: DictavaTheme.radiusSm + 3)
                                .fill(theme.bg)
                        )
                    }

                    Divider().overlay(theme.border)
                    Toggle("Launch at login", isOn: $settingsStore.launchAtLogin)
                        .onChange(of: settingsStore.launchAtLogin) { _, _ in
                            NSApp.sendAction(#selector(AppDelegate.updateLaunchAtLogin), to: nil, from: nil)
                        }
                }
            }
        }
    }

    // MARK: - Models

    private var isParakeetActive: Bool {
        settingsStore.preferredProvider(for: settingsStore.selectedLanguage) == .fluidAudio
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: DictavaTheme.spacing8) {
            sectionLabel("MODELS")

            // Parakeet
            DictavaCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Parakeet v3")
                                .font(.callout)
                                .foregroundStyle(theme.textPrimary)
                            if isParakeetActive && fluidAudioModelManager.isDownloaded {
                                Text("Active")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(theme.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(theme.accentDim))
                            }
                        }
                        Text("\(FluidAudioModelManager.size) \u{00B7} \(FluidAudioModelManager.speed)")
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                    }

                    Spacer()

                    if fluidAudioModelManager.isDownloading {
                        HStack(spacing: 6) {
                            ProgressView(value: fluidAudioModelManager.downloadProgress, total: 1.0)
                                .tint(theme.accent)
                                .frame(width: 60)
                            Text("\(Int(fluidAudioModelManager.downloadProgress * 100))%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(theme.textSecondary)
                        }
                    } else if fluidAudioModelManager.isDownloaded {
                        if !isParakeetActive {
                            Button("Select") {
                                settingsStore.setPreferredProvider(.fluidAudio, for: settingsStore.selectedLanguage)
                                dictationSession.switchProvider(to: .fluidAudio)
                            }
                            .buttonStyle(EmberGhostButtonStyle())
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.success)
                                .font(.caption)
                        }
                    } else {
                        Button("Download") {
                            fluidAudioModelManager.downloadModel()
                        }
                        .buttonStyle(AccentButtonStyle())
                    }
                }
            }

            // WhisperKit models
            DictavaCard {
                VStack(alignment: .leading, spacing: DictavaTheme.spacing12) {
                    Text("WhisperKit Models")
                        .font(.callout)
                        .foregroundStyle(isParakeetActive ? theme.textMuted : theme.textPrimary)

                    let models = modelManager.models(for: settingsStore.selectedLanguage)

                    if models.isEmpty {
                        Text("Loading models...")
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                    } else {
                        ForEach(models) { model in
                            whisperModelRow(model)
                            if model.id != models.last?.id {
                                Divider().overlay(theme.border)
                            }
                        }
                    }
                }
            }
        }
    }

    private func whisperModelRow(_ model: WhisperModel) -> some View {
        let isSelected = settingsStore.selectedModelName == model.name
        let isWhisperActive = !isParakeetActive

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.callout)
                        .foregroundStyle(isParakeetActive ? theme.textMuted : theme.textPrimary)
                    if isSelected && isWhisperActive {
                        Text("Active")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(theme.accentDim))
                    }
                }
                Text("\(model.size) \u{00B7} \(model.speed)")
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
            }

            Spacer()

            if model.isDownloading {
                ProgressView(value: model.downloadProgress, total: 1.0)
                    .tint(theme.accent)
                    .frame(width: 60)
            } else if model.isDownloaded {
                if !(isSelected && isWhisperActive) {
                    Button("Select") {
                        settingsStore.selectedModelName = model.name
                        settingsStore.setPreferredProvider(.whisperKit, for: settingsStore.selectedLanguage)
                        dictationSession.switchProvider(to: .whisperKit, modelName: model.name)
                    }
                    .buttonStyle(EmberGhostButtonStyle())
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                        .font(.caption)
                }
            } else {
                Button("Download") {
                    modelManager.downloadModel(model)
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
    }

    // MARK: - Indicator Style

    private var indicatorSection: some View {
        VStack(alignment: .leading, spacing: DictavaTheme.spacing8) {
            sectionLabel("INDICATOR STYLE")

            DictavaCard {
                HStack(spacing: DictavaTheme.spacing8) {
                    ForEach(IndicatorTheme.allPresets) { preset in
                        indicatorPresetPill(preset)
                    }
                }
            }
        }
    }

    private func indicatorPresetPill(_ preset: IndicatorTheme) -> some View {
        let isSelected = settingsStore.indicatorThemeName == preset.id

        return Button {
            settingsStore.indicatorThemeName = preset.id
        } label: {
            VStack(spacing: DictavaTheme.spacing4) {
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .fill(preset.backgroundColor)
                    .frame(height: 32)
                    .overlay {
                        // Mini waveform preview
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(preset.waveformColor)
                                    .frame(width: 3, height: CGFloat([8, 14, 20, 12, 6][i]))
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                            .stroke(isSelected ? preset.waveformColor : theme.border, lineWidth: isSelected ? 2 : 1)
                    )

                Text(preset.label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: DictavaTheme.spacing8) {
            sectionLabel("DATA")

            DictavaCard {
                VStack(spacing: DictavaTheme.spacing12) {
                    dataRow("Clear History", buttonLabel: "Clear") {
                        transcriptionLogStore.deleteAllLogs()
                    }
                    Divider().overlay(theme.border)
                    dataRow("Reset Settings", buttonLabel: "Reset") {
                        if let bundleID = Bundle.main.bundleIdentifier {
                            UserDefaults.standard.removePersistentDomain(forName: bundleID)
                        }
                        NSApp.sendAction(#selector(AppDelegate.updateLaunchAtLogin), to: nil, from: nil)
                        NSApp.sendAction(#selector(AppDelegate.updateHoldToRecord), to: nil, from: nil)
                    }
                }
            }
        }
    }

    private func dataRow(_ label: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button(buttonLabel, action: action)
                .buttonStyle(EmberDestructiveButtonStyle())
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DictavaTheme.spacing8) {
            sectionLabel("ABOUT")

            DictavaCard {
                VStack(alignment: .leading, spacing: DictavaTheme.spacing8) {
                    Text("Local, private dictation for macOS")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)

                    Text("MIT License")
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)

                    HStack(spacing: DictavaTheme.spacing16) {
                        Link("GitHub", destination: URL(string: "https://github.com/julian0xff/Dictava")!)
                            .font(.callout)
                            .foregroundStyle(theme.accent)

                        Link("Releases", destination: URL(string: "https://github.com/julian0xff/Dictava/releases")!)
                            .font(.callout)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
        }
    }

    // MARK: - Quit

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit Dictava")
        }
        .buttonStyle(EmberDestructiveButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.textMuted)
            .tracking(0.5)
    }
}

// MARK: - Hold Key Recorder

struct HoldKeyRecorderButton: View {
    @Binding var keyName: String
    @Binding var keyCode: Int
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            HStack(spacing: 6) {
                Text(isRecording ? "Press a key\u{2026}" : keyName)
                    .fontWeight(isRecording ? .regular : .medium)
                    .foregroundStyle(isRecording ? theme.textSecondary : theme.textPrimary)
                if !isRecording {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .fill(isRecording ? theme.accent.opacity(0.1) : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .stroke(isRecording ? theme.accent : theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        (NSApp.delegate as? AppDelegate)?.holdToRecordManager.isCapturingKey = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = Int64(event.keyCode)
            guard !HoldToRecordManager.excludedKeyCodes.contains(code) else { return nil }
            keyCode = Int(code)
            keyName = HoldToRecordManager.displayName(for: code)
            stopRecording()
            (NSApp.delegate as? AppDelegate)?.updateHoldToRecord()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        (NSApp.delegate as? AppDelegate)?.holdToRecordManager.isCapturingKey = false
    }
}
