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
        }
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
