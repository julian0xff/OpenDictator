import Foundation
import Combine

@MainActor
final class TranscriptionEngine: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isTranscribing = false
    @Published var partialText = ""
    @Published var confirmedText = ""
    private(set) var loadedModelName: String?

    private var provider: ASRProvider?
    private nonisolated(unsafe) var appendToProvider: (([Float]) -> Void)?

    var activeProviderID: ASRProviderID? {
        provider?.id
    }

    func setProvider(_ provider: ASRProvider) {
        self.provider = provider
        self.appendToProvider = { samples in provider.appendAudioBuffer(samples) }
        syncState()
    }

    func loadModel(named modelName: String? = nil) async throws {
        guard let provider else { return }
        try await provider.loadModel(named: modelName)
        syncState()
    }

    func unloadModel() {
        provider?.unloadModel()
        syncState()
    }

    nonisolated func appendAudioBuffer(_ samples: [Float]) {
        appendToProvider?(samples)
    }

    /// Set synchronously before any await — blocks all new partials from starting.
    private var isFinalPending = false
    /// True while a partial transcription is awaiting the provider.
    private var isPartialInFlight = false
    /// True while a final or checkpoint transcription is awaiting the provider.
    private var isFinalInFlight = false

    func transcribe(language: String = "en") async -> String {
        guard let provider else { return "" }

        while isFinalInFlight {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }

        // Block new partials immediately (synchronous, before any await).
        // Any queued timer Tasks that run after this point will see isFinalPending
        // and skip, so no new partials can sneak in.
        isFinalPending = true
        isFinalInFlight = true
        defer {
            isFinalPending = false
            isFinalInFlight = false
        }

        // Wait for any in-progress partial to finish
        while isPartialInFlight {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let text = await provider.transcribe(language: language)
        guard !text.isEmpty else { return "" }
        confirmedText = text
        return text
    }

    func transcribeCheckpoint(language: String = "en") async -> String {
        guard let provider else { return "" }

        while isFinalInFlight {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }

        isFinalPending = true
        isFinalInFlight = true
        defer {
            isFinalPending = false
            isFinalInFlight = false
        }

        while isPartialInFlight {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }

        return await provider.transcribeCheckpoint(language: language)
    }

    func transcribePartial(language: String = "en") async {
        guard let provider else { return }
        guard !isPartialInFlight && !isFinalPending else { return }

        isPartialInFlight = true
        defer { isPartialInFlight = false }

        let text = await provider.transcribePartial(language: language)
        guard !text.isEmpty else { return }
        partialText = text
    }

    func flushAudioBuffer() async {
        await provider?.flushAudioBuffer()
    }

    func reset() async {
        await provider?.reset()
        partialText = ""
        confirmedText = ""
        isFinalPending = false
        isPartialInFlight = false
        isFinalInFlight = false
        isTranscribing = false
    }

    func bufferedSampleCount() async -> Int {
        await provider?.bufferedSampleCount() ?? 0
    }

    private func syncState() {
        isModelLoaded = provider?.isModelLoaded ?? false
        loadedModelName = provider?.loadedModelName
    }
}
