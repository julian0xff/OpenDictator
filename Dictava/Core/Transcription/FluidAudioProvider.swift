import Foundation
import FluidAudio

@MainActor
final class FluidAudioProvider: ASRProvider {
    let id: ASRProviderID = .fluidAudio
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String? = nil

    private var asrManager: AsrManager?
    private let fullSampleBuffer = AudioSampleBuffer()
    private let partialSampleBuffer = AudioSampleBuffer(maxSamples: 16_000 * 30) // Last 30s for low-latency partials
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
            await fullSampleBuffer.append(samples)
            await partialSampleBuffer.append(samples)
        }
    }

    func flushAudioBuffer() async {
        await fullSampleBuffer.flush()
        await partialSampleBuffer.flush()
    }

    func transcribe(language: String) async -> String {
        guard let asrManager else { return "" }

        let samples = await fullSampleBuffer.getAll()
        guard samples.count >= 1600 else { return "" }  // Minimum ~0.1 seconds

        do {
            let result = try await asrManager.transcribe(samples, source: .microphone)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("FluidAudio transcription error: \(error)")
            return ""
        }
    }

    func transcribeCheckpoint(language: String) async -> String {
        guard let asrManager else { return "" }

        let samples = await fullSampleBuffer.drainAll()
        guard samples.count >= 1600 else { return "" }

        // Re-seed with last 5s for acoustic context after drain
        let contextWindow = 16_000 * 5
        if samples.count > contextWindow {
            await fullSampleBuffer.append(Array(samples.suffix(contextWindow)))
        }
        await partialSampleBuffer.clear()

        do {
            let result = try await asrManager.transcribe(samples, source: .microphone)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    func transcribeCheckpointFlushed(language: String) async -> String {
        await flushAudioBuffer()
        return await transcribeCheckpoint(language: language)
    }

    func transcribePartial(language: String) async -> String {
        guard let asrManager else { return "" }

        let samples = await partialSampleBuffer.getAll()
        guard samples.count >= 1600 else { return "" }

        do {
            let result = try await asrManager.transcribe(samples, source: .microphone)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    func reset() async {
        await fullSampleBuffer.clear()
        await partialSampleBuffer.clear()
        try? await asrManager?.resetDecoderState(for: .microphone)
    }

    func clearBuffers() async {
        await fullSampleBuffer.clear()
        await partialSampleBuffer.clear()
    }

    func bufferedSampleCount() async -> Int {
        await fullSampleBuffer.count()
    }
}
