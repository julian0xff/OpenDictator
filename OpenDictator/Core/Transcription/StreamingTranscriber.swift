import AVFoundation
import Combine

/// Bridges AudioCaptureEngine buffers into TranscriptionEngine samples,
/// and triggers periodic partial transcriptions for live preview.
@MainActor
final class StreamingTranscriber: ObservableObject {
    @Published var liveText = ""

    private let transcriptionEngine: TranscriptionEngine
    private var cancellables = Set<AnyCancellable>()
    private var partialTimer: Timer?
    private var language: String = "en"

    init(transcriptionEngine: TranscriptionEngine) {
        self.transcriptionEngine = transcriptionEngine
    }

    func startStreaming(from audioEngine: AudioCaptureEngine, language: String, partialInterval: TimeInterval = 1.5) async {
        self.language = language
        await transcriptionEngine.reset()

        audioEngine.audioBufferPublisher
            .sink { [weak self] buffer in
                self?.handleBuffer(buffer)
            }
            .store(in: &cancellables)

        // Trigger partial transcription at the specified interval for live preview
        let timer = Timer(timeInterval: partialInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.transcriptionEngine.transcribePartial(language: self.language)
                self.liveText = self.transcriptionEngine.partialText
            }
        }
        timer.tolerance = partialInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        partialTimer = timer
    }

    func stopStreaming() async -> String {
        cancellables.removeAll()
        partialTimer?.invalidate()
        partialTimer = nil

        // Drain any in-flight appendAudioBuffer Tasks before reading the buffer
        await transcriptionEngine.flushAudioBuffer()

        let finalText = await transcriptionEngine.transcribe(language: language)
        liveText = ""
        return finalText
    }

    /// Force-cancel streaming without performing final transcription.
    /// Used when the user restarts dictation mid-processing.
    func cancelStreaming() {
        cancellables.removeAll()
        partialTimer?.invalidate()
        partialTimer = nil
        liveText = ""
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))
        transcriptionEngine.appendAudioBuffer(samples)
    }
}
