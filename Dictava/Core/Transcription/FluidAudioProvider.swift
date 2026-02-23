import Foundation
import FluidAudio

@MainActor
final class FluidAudioProvider: ASRProvider {
    let id: ASRProviderID = .fluidAudio
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String? = nil

    private var asrManager: AsrManager?
    private let sampleBuffer = AudioSampleBuffer()
    weak var fluidAudioModelManager: FluidAudioModelManager?

    func loadModel(named modelName: String?) async throws {
        // Reuse cached models from FluidAudioModelManager if available
        let models: AsrModels
        if let cached = fluidAudioModelManager?.cachedModels {
            models = cached
        } else {
            models = try await AsrModels.downloadAndLoad(version: .v3)
        }
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        asrManager = manager
        loadedModelName = "parakeet-v3"
        isModelLoaded = true
    }

    func unloadModel() {
        asrManager?.cleanup()
        asrManager = nil
        loadedModelName = nil
        isModelLoaded = false
    }

    nonisolated func appendAudioBuffer(_ samples: [Float]) {
        Task {
            await sampleBuffer.append(samples)
        }
    }

    func flushAudioBuffer() async {
        await sampleBuffer.flush()
    }

    func transcribe(language: String) async -> String {
        guard let asrManager else { return "" }

        let samples = await sampleBuffer.getAll()
        guard samples.count >= 1600 else { return "" }  // Minimum ~0.1 seconds

        do {
            let result = try await asrManager.transcribe(samples, source: .microphone)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("FluidAudio transcription error: \(error)")
            return ""
        }
    }

    func transcribePartial(language: String) async -> String {
        guard let asrManager else { return "" }

        let samples = await sampleBuffer.getAll()
        guard samples.count >= 1600 else { return "" }

        do {
            let result = try await asrManager.transcribe(samples, source: .microphone)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    func reset() async {
        await sampleBuffer.clear()
        try? await asrManager?.resetDecoderState(for: .microphone)
    }
}
