import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject private var permissionManager = PermissionManager.shared

    var body: some View {
        Form {
            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Toggle Dictation:", name: .toggleDictation)
                KeyboardShortcuts.Recorder("Copy Last Transcription:", name: .copyLastTranscription)
            }

            Section("Behavior") {
                Toggle("Play start/stop sounds", isOn: $settingsStore.playStartStopSounds)
                Toggle("Show floating indicator", isOn: $settingsStore.showFloatingIndicator)
                Toggle("Show dock icon", isOn: $settingsStore.showDockIcon)
                    .onChange(of: settingsStore.showDockIcon) { _ in
                        (NSApp.delegate as? AppDelegate)?.updateDockIconPolicy()
                    }
                Toggle("Launch at login", isOn: $settingsStore.launchAtLogin)
            }

            Section("Permissions") {
                PermissionStatusRow(
                    title: "Microphone",
                    status: permissionManager.microphoneStatus,
                    action: {
                        Task { await permissionManager.requestMicrophone() }
                    }
                )
                PermissionStatusRow(
                    title: "Accessibility",
                    status: permissionManager.accessibilityStatus,
                    action: {
                        permissionManager.requestAccessibility()
                    }
                )
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionStatusRow: View {
    let title: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
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
