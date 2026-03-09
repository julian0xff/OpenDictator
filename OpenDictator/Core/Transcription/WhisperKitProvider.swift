import Foundation
import WhisperKit

@MainActor
final class WhisperKitProvider: ASRProvider {
    let id: ASRProviderID = .whisperKit
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?

    private var whisperKit: WhisperKit?
    private let fullSampleBuffer = AudioSampleBuffer()
    private let partialSampleBuffer = AudioSampleBuffer(maxSamples: 16_000 * 30) // Last 30s for low-latency partials

    func loadModel(named modelName: String?) async throws {
        guard let modelName else { return }
        whisperKit = try await WhisperKit(
            model: modelName,
            verbose: false,
            logLevel: .none
        )
        loadedModelName = modelName
        isModelLoaded = true
    }

    func unloadModel() {
        whisperKit = nil
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
        guard let whisperKit else { return "" }

        let samples = await fullSampleBuffer.getAll()
        guard !samples.isEmpty else { return "" }

        do {
            let options = DecodingOptions(language: language)
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let rawText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.stripNonSpeechAnnotations(rawText)
        } catch {
            print("Transcription error: \(error)")
            return ""
        }
    }

    func transcribeCheckpoint(language: String) async -> String {
        guard let whisperKit else { return "" }

        let samples = await fullSampleBuffer.drainAll()
        guard !samples.isEmpty else { return "" }

        // Re-seed with last 5s for acoustic context after drain
        let contextWindow = 16_000 * 5
        if samples.count > contextWindow {
            await fullSampleBuffer.append(Array(samples.suffix(contextWindow)))
        }
        await partialSampleBuffer.clear()

        do {
            let options = DecodingOptions(language: language)
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let rawText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.stripNonSpeechAnnotations(rawText)
        } catch {
            return ""
        }
    }

    func transcribeCheckpointFlushed(language: String) async -> String {
        await flushAudioBuffer()
        return await transcribeCheckpoint(language: language)
    }

    func transcribePartial(language: String) async -> String {
        guard let whisperKit else { return "" }

        let samples = await partialSampleBuffer.getAll()
        guard !samples.isEmpty else { return "" }

        do {
            let options = DecodingOptions(language: language)
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let rawText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.stripNonSpeechAnnotations(rawText)
        } catch {
            return ""
        }
    }

    func reset() async {
        await fullSampleBuffer.clear()
        await partialSampleBuffer.clear()
    }

    func clearBuffers() async {
        await fullSampleBuffer.clear()
        await partialSampleBuffer.clear()
    }

    func bufferedSampleCount() async -> Int {
        await fullSampleBuffer.count()
    }

    /// Strips non-speech annotations that Whisper hallucinates from its training data (YouTube subtitles).
    /// Matches anything in brackets or parentheses like [Silence], [clears throat], (laughter), [BLANK_AUDIO],
    /// [music], [applause], [coughing], [sneezing], etc. Real speech never produces bracketed text.
    /// Also strips music symbols (♪♫♬) that Whisper outputs for background music.
    private static func stripNonSpeechAnnotations(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[♩♪♫♬♭♮♯]+"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
