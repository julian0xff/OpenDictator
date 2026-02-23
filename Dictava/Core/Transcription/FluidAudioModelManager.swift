import SwiftUI
import FluidAudio

@MainActor
final class FluidAudioModelManager: ObservableObject {
    @Published var isDownloaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?

    static let displayName = "Parakeet v3"
    static let size = "~470 MB"
    static let speed = "~190ms"

    /// Known model size on disk (~470 MB). Used for progress estimation.
    private static let expectedModelSize: Int64 = 493_000_000

    /// Cached models from download — provider can reuse instead of re-downloading
    private(set) var cachedModels: AsrModels?
    weak var fluidAudioProvider: FluidAudioProvider?

    private var downloadTask: Task<Void, Never>?
    private var progressTimer: Timer?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        isDownloaded = AsrModels.modelsExist(at: cacheDir, version: .v3)
    }

    func downloadModel() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        startProgressPolling()

        downloadTask = Task {
            do {
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                cachedModels = models
                isDownloaded = true
                downloadProgress = 1.0
            } catch {
                if !Task.isCancelled {
                    downloadError = error.localizedDescription
                }
            }
            stopProgressPolling()
            isDownloading = false
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        stopProgressPolling()
        downloadProgress = 0
        isDownloading = false

        // Clean up partial download files
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        if !AsrModels.modelsExist(at: cacheDir, version: .v3) {
            try? FileManager.default.removeItem(at: cacheDir)
        }
        refreshStatus()
    }

    // MARK: - Progress Polling

    private func startProgressPolling() {
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isDownloading else { return }
                let size = Self.directorySize(at: cacheDir)
                self.downloadProgress = min(Double(size) / Double(Self.expectedModelSize), 0.99)
            }
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        return total
    }

    func deleteModel() {
        // Unload the provider if it's using this model
        fluidAudioProvider?.unloadModel()
        cachedModels = nil

        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        try? FileManager.default.removeItem(at: cacheDir)
        isDownloaded = false
    }
}
