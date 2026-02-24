import SwiftUI
import FluidAudio

struct AdvancedSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var transcriptionLogStore: TranscriptionLogStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager

    @State private var showResetAlert = false
    @State private var showClearHistoryAlert = false
    @State private var showDeleteModelsAlert = false
    @State private var storageSizes: StorageSizes = .empty

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var appDataDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dictava", isDirectory: true)
    }

    private var whisperKitModelsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    private var parakeetModelDir: URL {
        AsrModels.defaultCacheDirectory(for: .v3)
    }

    var body: some View {
        ScrollView {
            Form {
                // About
                Section {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(14)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dictava")
                                .font(.title2.bold())
                            Text("v\(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Local, private dictation for macOS")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            Button {
                                NSWorkspace.shared.open(URL(string: "https://github.com/julian0xff/Dictava")!)
                            } label: {
                                Label("GitHub", systemImage: "link")
                            }
                            .buttonStyle(.borderless)

                            Button {
                                NSWorkspace.shared.open(URL(string: "https://github.com/julian0xff/Dictava/releases")!)
                            } label: {
                                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderless)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("License")
                        Spacer()
                        Text("MIT")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SettingsSectionHeader(icon: "info.circle", title: "About Dictava", color: .blue)
                }

                // Data & Storage
                Section {
                    // App Data group
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Data")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    storageRow("Transcription history", file: "transcription_logs.json")
                    storageRow("Snippets", file: "snippets.yml")
                    storageRow("Custom vocabulary", file: "vocabulary.json")
                    storageRow("Custom themes", file: "custom_themes.json")
                    storageRow("Custom voice commands", file: "custom_voice_commands.json")

                    Button("Open App Data Folder") {
                        NSWorkspace.shared.open(appDataDir)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Divider()

                    // Models group
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Models")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("WhisperKit models")
                            .font(.caption)
                        Spacer()
                        Text(storageSizes.whisperKit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Parakeet model")
                            .font(.caption)
                        Spacer()
                        Text(storageSizes.parakeet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Open WhisperKit Models") {
                            NSWorkspace.shared.open(whisperKitModelsDir)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        if FileManager.default.fileExists(atPath: parakeetModelDir.path) {
                            Button("Open Parakeet Model") {
                                NSWorkspace.shared.open(parakeetModelDir)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total storage used")
                            .fontWeight(.medium)
                        Spacer()
                        Text(storageSizes.total)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SettingsSectionHeader(icon: "externaldrive", title: "Data & Storage", color: .orange)
                }

                // Danger Zone
                Section {
                    Button("Reset All Settings") {
                        showResetAlert = true
                    }
                    .foregroundStyle(.red)

                    Button("Clear History") {
                        showClearHistoryAlert = true
                    }
                    .foregroundStyle(.red)

                    Button("Delete All Models") {
                        showDeleteModelsAlert = true
                    }
                    .foregroundStyle(.red)
                } header: {
                    SettingsSectionHeader(icon: "exclamationmark.triangle", title: "Danger Zone", color: .red)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { refreshStorageSizes() }
        .alert("Reset All Settings", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            }
        } message: {
            Text("All settings will be restored to defaults. This cannot be undone.")
        }
        .alert("Clear History", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                transcriptionLogStore.deleteAllLogs()
                refreshStorageSizes()
            }
        } message: {
            Text("All transcription history will be permanently deleted.")
        }
        .alert("Delete All Models", isPresented: $showDeleteModelsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAllModels()
                refreshStorageSizes()
            }
        } message: {
            Text("All downloaded speech models (WhisperKit and Parakeet) will be deleted. You'll need to re-download them to use dictation.")
        }
    }

    // MARK: - Storage Helpers

    private func storageRow(_ label: String, file: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(fileSize(at: appDataDir.appendingPathComponent(file)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshStorageSizes() {
        storageSizes = StorageSizes(
            whisperKit: directorySize(at: whisperKitModelsDir),
            parakeet: FileManager.default.fileExists(atPath: parakeetModelDir.path)
                ? directorySize(at: parakeetModelDir) : "Not downloaded",
            total: totalSize()
        )
    }

    private func fileSize(at url: URL) -> String {
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else {
            return "—"
        }
        return formatBytes(size)
    }

    private func directorySize(at url: URL) -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 B"
        }
        var totalSize: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = attrs.fileSize {
                totalSize += UInt64(size)
            }
        }
        return formatBytes(totalSize)
    }

    private func totalSize() -> String {
        var total: UInt64 = 0

        // App data
        let fm = FileManager.default
        let dataFiles = ["transcription_logs.json", "snippets.yml", "vocabulary.json", "custom_themes.json", "custom_voice_commands.json"]
        for file in dataFiles {
            let path = appDataDir.appendingPathComponent(file).path
            if let attrs = try? fm.attributesOfItem(atPath: path), let size = attrs[.size] as? UInt64 {
                total += size
            }
        }

        // WhisperKit models
        if let enumerator = fm.enumerator(at: whisperKitModelsDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                    total += UInt64(size)
                }
            }
        }

        // Parakeet model
        if fm.fileExists(atPath: parakeetModelDir.path),
           let enumerator = fm.enumerator(at: parakeetModelDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                    total += UInt64(size)
                }
            }
        }

        return formatBytes(total)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func deleteAllModels() {
        // Delete WhisperKit models via manager
        for model in modelManager.availableModels where model.isDownloaded {
            modelManager.deleteModel(model)
        }

        // Delete Parakeet model via manager (updates isDownloaded state)
        if fluidAudioModelManager.isDownloaded {
            fluidAudioModelManager.deleteModel()
        }

        // Clean up empty Models dir in app support (leftover)
        let emptyModelsDir = appDataDir.appendingPathComponent("Models")
        if FileManager.default.fileExists(atPath: emptyModelsDir.path) {
            try? FileManager.default.removeItem(at: emptyModelsDir)
        }
    }
}

private struct StorageSizes {
    let whisperKit: String
    let parakeet: String
    let total: String

    static let empty = StorageSizes(whisperKit: "...", parakeet: "...", total: "...")
}
