import SwiftUI
import WhisperKit
import Combine

struct WhisperModel: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let size: String
    let speed: String
    let description: String
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
}

@MainActor
final class ModelManager: ObservableObject {
    @Published var availableModels: [WhisperModel] = []
    @Published var isLoadingModelList = false

    private let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dictava/Models", isDirectory: true)
    }()

    static let defaultModels: [WhisperModel] = [
        WhisperModel(id: "openai_whisper-tiny.en", name: "openai_whisper-tiny.en",
                     displayName: "Tiny (English)", size: "~39 MB", speed: "~275ms",
                     description: "Fast dictation, English only"),
        WhisperModel(id: "openai_whisper-base.en", name: "openai_whisper-base.en",
                     displayName: "Base (English)", size: "~74 MB", speed: "~500ms",
                     description: "Good balance of speed and accuracy"),
        WhisperModel(id: "openai_whisper-small.en", name: "openai_whisper-small.en",
                     displayName: "Small (English)", size: "~244 MB", speed: "~1.5s",
                     description: "Better accuracy for longer dictation"),
        WhisperModel(id: "openai_whisper-large-v3_turbo", name: "openai_whisper-large-v3_turbo",
                     displayName: "Large v3 Turbo", size: "~809 MB", speed: "~3s",
                     description: "Best quality, multilingual support"),
    ]

    init() {
        createModelsDirectoryIfNeeded()
        refreshDownloadedStatus()
    }

    func refreshDownloadedStatus() {
        var models = Self.defaultModels
        let downloadedModels = listDownloadedModels()

        for i in models.indices {
            models[i].isDownloaded = downloadedModels.contains(models[i].name)
        }

        availableModels = models
    }

    func downloadModel(_ model: WhisperModel) async throws {
        guard let index = availableModels.firstIndex(where: { $0.id == model.id }) else { return }

        availableModels[index].isDownloading = true
        availableModels[index].downloadProgress = 0

        do {
            // WhisperKit handles model downloading to its own hub directory
            _ = try await WhisperKit(model: model.name, verbose: false, logLevel: .none)
            availableModels[index].isDownloaded = true
        } catch {
            throw error
        }

        availableModels[index].isDownloading = false
        availableModels[index].downloadProgress = 1.0
    }

    func deleteModel(_ model: WhisperModel) {
        let hubDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/\(model.name)", isDirectory: true)
        try? FileManager.default.removeItem(at: hubDir)
        refreshDownloadedStatus()
    }

    private func createModelsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    private func listDownloadedModels() -> Set<String> {
        // WhisperKit stores models in ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/
        let hubDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)

        guard let contents = try? FileManager.default.contentsOfDirectory(at: hubDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return Set(contents.map { $0.lastPathComponent })
    }
}
