import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject private var permissionManager = PermissionManager.shared

    var body: some View {
        ScrollView {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Dictation:", name: .toggleDictation)
                KeyboardShortcuts.Recorder("Copy Last Transcription:", name: .copyLastTranscription)
            } header: {
                SettingsSectionHeader(icon: "keyboard", title: "Hotkeys", color: .blue)
            }

            Section {
                Toggle("Enable hold-to-record", isOn: $settingsStore.holdToRecordEnabled)
                    .onChange(of: settingsStore.holdToRecordEnabled) { _ in
                        (NSApp.delegate as? AppDelegate)?.updateHoldToRecord()
                    }

                if settingsStore.holdToRecordEnabled {
                    HStack {
                        Text("Hold key:")
                        Spacer()
                        HoldKeyRecorderButton(
                            keyCode: $settingsStore.holdToRecordKeyCode,
                            keyName: $settingsStore.holdToRecordKeyName
                        )
                    }

                    Text("Hold the key to start recording, release to transcribe. The key is consumed by Dictava and won't reach other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if permissionManager.accessibilityStatus != .granted {
                        Label("Accessibility permission required for key interception", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if !settingsStore.holdToRecordTapActive {
                        Label("Key interception failed to start. Try toggling the feature off and on, or re-grant Accessibility permission.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                SettingsSectionHeader(icon: "hand.raised", title: "Hold to Record", color: .orange)
            }

            Section {
                Toggle("Play start/stop sounds", isOn: $settingsStore.playStartStopSounds)
                Toggle("Show floating indicator", isOn: $settingsStore.showFloatingIndicator)
                Toggle("Show dock icon", isOn: $settingsStore.showDockIcon)
                    .onChange(of: settingsStore.showDockIcon) { _ in
                        (NSApp.delegate as? AppDelegate)?.updateDockIconPolicy()
                    }
                Toggle("Launch at login", isOn: $settingsStore.launchAtLogin)
            } header: {
                SettingsSectionHeader(icon: "gearshape.2", title: "Behavior", color: .purple)
            }

            Section {
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
            } header: {
                SettingsSectionHeader(icon: "lock.shield", title: "Permissions", color: .green)
            }
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: settingsStore.holdToRecordEnabled)
        }
    }
}

struct HoldKeyRecorderButton: View {
    @Binding var keyCode: Int
    @Binding var keyName: String
    @State private var isRecording = false
    @State private var keyMonitor: Any?

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
                    .foregroundStyle(isRecording ? .secondary : .primary)
                if !isRecording {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        (NSApp.delegate as? AppDelegate)?.holdToRecordManager.isCapturingKey = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let code = Int64(event.keyCode)

            // Reject modifier keys
            guard !HoldToRecordManager.excludedKeyCodes.contains(code) else {
                return nil
            }

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

struct PermissionStatusRow: View {
    let title: String
    var description: String? = nil
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch status {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Button("Grant Access") { action() }
            case .notDetermined:
                Button("Request") { action() }
            }
        }
    }
}
