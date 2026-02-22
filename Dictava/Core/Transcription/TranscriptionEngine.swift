import Foundation
import WhisperKit
import Combine

/// Thread-safe buffer for collecting audio samples from the audio callback
private actor AudioSampleBuffer {
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    func getAll() -> [Float] {
        samples
    }

    func clear() {
        samples.removeAll()
    }
}

@MainActor
final class TranscriptionEngine: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isTranscribing = false
    @Published var partialText = ""
    @Published var confirmedText = ""

    private var whisperKit: WhisperKit?
    private let sampleBuffer = AudioSampleBuffer()

    func loadModel(named modelName: String) async throws {
        whisperKit = try await WhisperKit(
            model: modelName,
            verbose: false,
            logLevel: .none
        )
        isModelLoaded = true
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }

    nonisolated func appendAudioBuffer(_ samples: [Float]) {
        Task {
            await sampleBuffer.append(samples)
        }
    }

    func transcribe() async -> String {
        guard let whisperKit else { return "" }

        let samples = await sampleBuffer.getAll()
        guard !samples.isEmpty else { return "" }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let results = try await whisperKit.transcribe(audioArray: samples)
            let rawText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = Self.stripNonSpeechAnnotations(rawText)
            guard !text.isEmpty else { return "" }
            confirmedText = text
            return text
        } catch {
            print("Transcription error: \(error)")
            return ""
        }
    }

    func transcribePartial() async {
        guard let whisperKit else { return }

        let samples = await sampleBuffer.getAll()
        guard !samples.isEmpty else { return }

        do {
            let results = try await whisperKit.transcribe(audioArray: samples)
            let rawText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = Self.stripNonSpeechAnnotations(rawText)
            guard !text.isEmpty else { return }
            partialText = text
        } catch {
            // Partial transcription errors are expected during streaming
        }
    }

    /// Strips non-speech annotations that Whisper hallucinates from its training data (YouTube subtitles).
    /// Matches anything in brackets or parentheses like [Silence], [clears throat], (laughter), [BLANK_AUDIO],
    /// [music], [applause], [coughing], [sneezing], etc. Real speech never produces bracketed text.
    /// Also strips music symbols (♪♫♬) that Whisper outputs for background music.
    private static func stripNonSpeechAnnotations(_ text: String) -> String {
        var result = text
        // Remove bracketed annotations: [Silence], [clears throat], [BLANK_AUDIO], etc.
        result = result.replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
        // Remove parenthesized annotations: (laughter), (silence), (music), etc.
        result = result.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
        // Remove music symbols: ♪, ♫, ♬, ♩, ♭, ♮, ♯
        result = result.replacingOccurrences(of: #"[♩♪♫♬♭♮♯]+"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        Task {
            await sampleBuffer.clear()
        }
        partialText = ""
        confirmedText = ""
    }
}
