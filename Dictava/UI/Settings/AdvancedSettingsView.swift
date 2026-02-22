import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Text Injection") {
                Text("Text is injected via clipboard simulation (Cmd+V). The original clipboard contents are saved and restored after a 200ms delay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                HStack {
                    Text("All data stored locally")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Data Folder") {
                        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        let dir = appSupport.appendingPathComponent("Dictava")
                        NSWorkspace.shared.open(dir)
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("Dictava")
                    Spacer()
                    Text("v0.1.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("License")
                    Spacer()
                    Text("MIT")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Reset All Settings", role: .destructive) {
                    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
                }
            }
        }
        .formStyle(.grouped)
    }
}
