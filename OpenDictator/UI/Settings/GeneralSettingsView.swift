import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject private var permissionManager = PermissionManager.shared
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: SettingsTheme.spacing16) {
                SettingsCard(title: "Hotkeys") {
                    VStack(spacing: SettingsTheme.spacing12) {
                        HStack {
                            Text("Toggle Dictation:")
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .toggleDictation)
                        }
                        HStack {
                            Text("Copy Last Transcription:")
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .copyLastTranscription)
                        }
                    }
                }

                SettingsCard(title: "Hold to Record") {
                    VStack(alignment: .leading, spacing: SettingsTheme.spacing12) {
                        Toggle("Enable hold-to-record", isOn: $settingsStore.holdToRecordEnabled)
                            .onChange(of: settingsStore.holdToRecordEnabled) { _, _ in
                                AppDelegate.shared?.updateHoldToRecord()
                            }

                        if settingsStore.holdToRecordEnabled {
                            HStack {
                                Text("Hold key:")
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                HoldKeyRecorderButton(
                                    keyCode: $settingsStore.holdToRecordKeyCode,
                                    keyName: $settingsStore.holdToRecordKeyName
                                )
                            }

                            Text("Hold the key to start recording, release to transcribe. The key is consumed by OpenDictator and won't reach other apps.")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)

                            if permissionManager.accessibilityStatus != .granted {
                                Label("Accessibility permission required for key interception", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(theme.warning)
                            } else if !settingsStore.holdToRecordTapActive {
                                Label("Key interception failed to start. Try toggling the feature off and on, or re-grant Accessibility permission.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(theme.warning)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: settingsStore.holdToRecordEnabled)
                }

                SettingsCard(title: "Behavior") {
                    VStack(spacing: SettingsTheme.spacing12) {
                        Toggle("Play start/stop sounds", isOn: $settingsStore.playStartStopSounds)
                        Toggle("Show floating indicator", isOn: $settingsStore.showFloatingIndicator)
                        Toggle("Show dock icon", isOn: $settingsStore.showDockIcon)
                            .onChange(of: settingsStore.showDockIcon) { _, newValue in
                                if !newValue && !settingsStore.showMenuBarIcon {
                                    settingsStore.showMenuBarIcon = true
                                }
                                AppDelegate.shared?.updateDockIconPolicy()
                            }
                        Toggle("Show menu bar icon", isOn: $settingsStore.showMenuBarIcon)
                            .onChange(of: settingsStore.showMenuBarIcon) { _, newValue in
                                if !newValue && !settingsStore.showDockIcon {
                                    settingsStore.showDockIcon = true
                                }
                                AppDelegate.shared?.updateDockIconPolicy()
                            }
                        Toggle("Launch at login", isOn: $settingsStore.launchAtLogin)
                            .onChange(of: settingsStore.launchAtLogin) { _, _ in
                                AppDelegate.shared?.updateLaunchAtLogin()
                            }
                        Toggle("Log transcription history", isOn: $settingsStore.logTranscriptionHistory)
                    }
                }

                SettingsCard(title: "Permissions") {
                    VStack(spacing: SettingsTheme.spacing12) {
                        PermissionStatusRow(
                            title: "Microphone",
                            description: "Required for voice capture",
                            status: permissionManager.microphoneStatus,
                            action: {
                                Task { await permissionManager.requestMicrophone() }
                            }
                        )
                        PermissionStatusRow(
                            title: "Accessibility",
                            description: "Required to type text at cursor",
                            status: permissionManager.accessibilityStatus,
                            action: {
                                permissionManager.requestAccessibility()
                            }
                        )
                    }
                }
            }
            .padding(SettingsTheme.spacing20)
        }
    }
}

struct HoldKeyRecorderButton: View {
    @Binding var keyCode: Int
    @Binding var keyName: String
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
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
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .fill(isRecording ? theme.controlAccent.opacity(0.1) : theme.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .stroke(isRecording ? theme.controlAccent : theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        AppDelegate.shared?.holdToRecordManager.isCapturingKey = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let code = Int64(event.keyCode)

            // Reject modifier keys
            guard !HoldToRecordManager.excludedKeyCodes.contains(code) else {
                return nil
            }

            keyCode = Int(code)
            keyName = HoldToRecordManager.displayName(for: code)
            stopRecording()
            AppDelegate.shared?.updateHoldToRecord()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        AppDelegate.shared?.holdToRecordManager.isCapturingKey = false
    }
}

struct PermissionStatusRow: View {
    let title: String
    var description: String? = nil
    let status: PermissionStatus
    let action: () -> Void
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(theme.textPrimary)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
            switch status {
            case .granted:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                        .padding(4)
                        .background(theme.successBackground)
                        .clipShape(Circle())
                    Text("Granted")
                        .foregroundStyle(theme.success)
                }
            case .denied:
                Button("Grant Access") { action() }
                    .buttonStyle(GhostButtonStyle())
            case .notDetermined:
                Button("Request") { action() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }
}
