import SwiftUI
import WhisperKit
import Combine

enum ModelTier: String, CaseIterable {
    case tiny, small, medium, large
}

struct WhisperModel: Identifiable {
    let id: String
    let name: String
    let tier: ModelTier
    let isMultilingual: Bool
    let displayName: String
    let size: String
    let speed: String
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
    var downloadError: String?
}

@MainActor
final class ModelManager: ObservableObject {
    @Published var availableModels: [WhisperModel] = []
    @Published var isLoadingModelList = false

    private let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OpenDictator/Models", isDirectory: true)
    }()

    static let defaultModels: [WhisperModel] = [
        // English-only models (`.en` — fine-tuned for English, better accuracy)
        WhisperModel(id: "openai_whisper-tiny.en", name: "openai_whisper-tiny.en",
                     tier: .tiny, isMultilingual: false,
                     displayName: "Tiny", size: "~153 MB", speed: "~275ms"),
        WhisperModel(id: "openai_whisper-small.en_217MB", name: "openai_whisper-small.en_217MB",
                     tier: .small, isMultilingual: false,
                     displayName: "Small", size: "~218 MB", speed: "~1.5s"),
        WhisperModel(id: "openai_whisper-medium.en", name: "openai_whisper-medium.en",
                     tier: .medium, isMultilingual: false,
                     displayName: "Medium", size: "~1.5 GB", speed: "~3s"),
        // Multilingual models (all languages including English)
        WhisperModel(id: "openai_whisper-tiny", name: "openai_whisper-tiny",
                     tier: .tiny, isMultilingual: true,
                     displayName: "Tiny", size: "~77 MB", speed: "~275ms"),
        WhisperModel(id: "openai_whisper-small_216MB", name: "openai_whisper-small_216MB",
                     tier: .small, isMultilingual: true,
                     displayName: "Small", size: "~217 MB", speed: "~1.5s"),
        WhisperModel(id: "openai_whisper-medium", name: "openai_whisper-medium",
                     tier: .medium, isMultilingual: true,
                     displayName: "Medium", size: "~1.5 GB", speed: "~3s"),
        // Large (multilingual only — no `.en` variant exists)
        WhisperModel(id: "openai_whisper-large-v3_turbo_954MB", name: "openai_whisper-large-v3_turbo_954MB",
                     tier: .large, isMultilingual: true,
                     displayName: "Large v3", size: "~1 GB", speed: "~3s"),
    ]

    init() {
        createModelsDirectoryIfNeeded()
        refreshDownloadedStatus()
    }

    /// Returns models appropriate for the given language code.
    /// English gets the `.en` optimized variants + large (always multilingual).
    /// All other languages get the multilingual variants only.
    func models(for language: String) -> [WhisperModel] {
        if language == "en" {
            return availableModels.filter { !$0.isMultilingual || $0.tier == .large }
        } else {
            return availableModels.filter { $0.isMultilingual }
        }
    }

    /// Returns the best model name for a given tier and language.
    /// Prefers the language-appropriate variant (`.en` for English, multilingual otherwise).
    func bestModel(tier: ModelTier, for language: String) -> String {
        let candidates = models(for: language)
        if let match = candidates.first(where: { $0.tier == tier }) {
            return match.name
        }
        // Fallback: first available model for this language
        return candidates.first?.name ?? Self.defaultModels[0].name
    }

    /// Returns the name of the smallest downloaded model for the given language, or nil if none downloaded.
    func bestDownloadedModel(for language: String) -> String? {
        models(for: language).first(where: { $0.isDownloaded })?.name
    }

    /// Determines the tier of a model by its name.
    func tier(for modelName: String) -> ModelTier {
        availableModels.first(where: { $0.name == modelName })?.tier ?? .tiny
    }

    func refreshDownloadedStatus() {
        let downloadedModels = listDownloadedModels()

        if availableModels.isEmpty {
            // First call (from init) — populate from defaults
            var models = Self.defaultModels
            for i in models.indices {
                models[i].isDownloaded = downloadedModels.contains(models[i].name)
            }
            availableModels = models
        } else {
            // Subsequent calls — only update isDownloaded, preserve transient state
            for i in availableModels.indices {
                availableModels[i].isDownloaded = downloadedModels.contains(availableModels[i].name)
            }
        }
    }

    private var downloadTask: Task<Void, Error>?

    func downloadModel(_ model: WhisperModel) {
        guard let index = availableModels.firstIndex(where: { $0.id == model.id }) else { return }

        availableModels[index].isDownloading = true
        availableModels[index].downloadProgress = 0
        availableModels[index].downloadError = nil

        downloadTask = Task {
            do {
                _ = try await WhisperKit.download(
                    variant: model.name,
                    progressCallback: { progress in
                        Task { @MainActor in
                            if let idx = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                                let newValue = progress.fractionCompleted
                                if newValue >= self.availableModels[idx].downloadProgress {
                                    self.availableModels[idx].downloadProgress = newValue
                                }
                            }
                        }
                    }
                )
                if let idx = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                    self.availableModels[idx].isDownloaded = true
                    self.availableModels[idx].isDownloading = false
                    self.availableModels[idx].downloadProgress = 1.0
                    self.availableModels[idx].downloadError = nil
                }
            } catch {
                if let idx = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                    self.availableModels[idx].isDownloading = false
                    if Task.isCancelled {
                        self.availableModels[idx].downloadProgress = 0
                    } else {
                        self.availableModels[idx].downloadError = error.localizedDescription
                    }
                }
            }
        }
    }

    func cancelDownload(_ model: WhisperModel) {
        downloadTask?.cancel()
        downloadTask = nil
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
