import Foundation

enum ASRProviderID: String, Codable, CaseIterable {
    case whisperKit = "whisperkit"
    case fluidAudio = "fluidaudio"
}

@MainActor
protocol ASRProvider: AnyObject {
    var id: ASRProviderID { get }
    var isModelLoaded: Bool { get }
    var loadedModelName: String? { get }

    /// Load a model by name. WhisperKit uses the variant name; FluidAudio ignores it (single model).
    func loadModel(named modelName: String?) async throws

    /// Unload the current model from memory.
    func unloadModel()

    /// Append audio samples from the capture callback. Must be safe to call from any thread.
    nonisolated func appendAudioBuffer(_ samples: [Float])

    /// Perform final transcription on accumulated audio.
    func transcribe(language: String) async -> String

    /// Perform transcription on a drained checkpoint buffer and clear that buffer.
    func transcribeCheckpoint(language: String) async -> String

    /// Perform partial transcription for live preview.
    func transcribePartial(language: String) async -> String

    /// Clear audio buffer and reset state.
    func reset() async

    /// Drain any in-flight audio append Tasks before reading the buffer.
    func flushAudioBuffer() async

    /// Drain any in-flight appends and transcribe+clear checkpoint audio atomically.
    func transcribeCheckpointFlushed(language: String) async -> String

    /// Clear audio sample buffers only (no decoder state reset).
    func clearBuffers() async

    /// Returns the number of buffered full-session samples.
    func bufferedSampleCount() async -> Int
}
