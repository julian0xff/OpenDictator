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

    init(transcriptionEngine: TranscriptionEngine) {
        self.transcriptionEngine = transcriptionEngine
    }

    func startStreaming(from audioEngine: AudioCaptureEngine) {
        transcriptionEngine.reset()

        audioEngine.audioBufferPublisher
            .sink { [weak self] buffer in
                self?.handleBuffer(buffer)
            }
            .store(in: &cancellables)

        // Trigger partial transcription every 1.5 seconds for live preview
        partialTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.transcriptionEngine.transcribePartial()
                self?.liveText = self?.transcriptionEngine.partialText ?? ""
            }
        }
    }

    func stopStreaming() async -> String {
        cancellables.removeAll()
        partialTimer?.invalidate()
        partialTimer = nil

        let finalText = await transcriptionEngine.transcribe()
        liveText = ""
        return finalText
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))
        transcriptionEngine.appendAudioBuffer(samples)
    }
}
