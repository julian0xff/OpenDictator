import SwiftUI
import Combine

@MainActor
final class DictationSession: ObservableObject {
    @Published var state: DictationState = .idle
    @Published var liveText = ""
    @Published var error: String?
    @Published var audioLevel: Float = 0
    @Published var audioLevelHistory: [Float] = Array(repeating: 0, count: 20)
    @Published var lastTranscription: String?

    private var sessionStartTime: Date?

    private let audioEngine = AudioCaptureEngine()
    private let transcriptionEngine = TranscriptionEngine()
    private lazy var streamingTranscriber = StreamingTranscriber(transcriptionEngine: transcriptionEngine)
    private let textInjector = TextInjector()
    private let commandExecutor = VoiceCommandExecutor()
    private let textPipeline: TextPipeline

    private let settingsStore: SettingsStore
    private let modelManager: ModelManager
    private let transcriptionLogStore: TranscriptionLogStore

    private var cancellables = Set<AnyCancellable>()
    private var liveTextCancellable: AnyCancellable?
    private var silenceCancellable: AnyCancellable?
    private var silenceTimer: Timer?
    private var longDictationTimer: Timer?

    init(settingsStore: SettingsStore, modelManager: ModelManager, snippetStore: SnippetStore, vocabularyStore: VocabularyStore, transcriptionLogStore: TranscriptionLogStore) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.transcriptionLogStore = transcriptionLogStore

        // Build the text processing pipeline
        textPipeline = TextPipeline()
        textPipeline.addProcessor(VoiceCommandParser(settingsStore: settingsStore))
        textPipeline.addProcessor(PunctuationHandler())
        textPipeline.addProcessor(SnippetExpander(snippetStore: snippetStore))
        textPipeline.addProcessor(FillerWordFilter())
        textPipeline.addProcessor(CustomVocabulary(vocabularyStore: vocabularyStore))
        textPipeline.addProcessor(LLMProcessor())

        // Forward audio levels for UI visualization
        audioEngine.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self else { return }
                self.audioLevel = level
                self.audioLevelHistory.append(level)
                if self.audioLevelHistory.count > 20 {
                    self.audioLevelHistory.removeFirst()
                }
            }
            .store(in: &cancellables)
    }

    func preloadModel() async {
        guard !transcriptionEngine.isModelLoaded else { return }
        try? await transcriptionEngine.loadModel(named: settingsStore.selectedModelName)
    }

    func switchModel(to modelName: String) {
        guard modelName != settingsStore.selectedModelName || !transcriptionEngine.isModelLoaded else { return }
        settingsStore.selectedModelName = modelName
        transcriptionEngine.unloadModel()
        Task {
            try? await transcriptionEngine.loadModel(named: modelName)
        }
    }

    func toggle() {
        if state == .idle {
            startDictation()
        } else {
            stopDictation()
        }
    }

    func startDictation() {
        guard state == .idle else { return }

        error = nil
        liveText = ""

        guard PermissionManager.shared.microphoneStatus == .granted else {
            error = "Microphone permission not granted"
            return
        }

        // Set state immediately to prevent re-entry from rapid toggling
        state = .listening
        sessionStartTime = Date()

        // Subscribe to live text for this session
        liveTextCancellable = streamingTranscriber.$liveText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.liveText = text
            }

        Task {
            // Ensure model is loaded
            if !transcriptionEngine.isModelLoaded {
                do {
                    try await transcriptionEngine.loadModel(named: settingsStore.selectedModelName)
                } catch {
                    self.error = "Failed to load model: \(error.localizedDescription)"
                    self.state = .idle
                    self.liveTextCancellable = nil
                    return
                }
            }

            do {
                try audioEngine.startCapturing()
                streamingTranscriber.startStreaming(from: audioEngine)

                if settingsStore.playStartStopSounds {
                    NSSound(named: "Tink")?.play()
                }

                startSilenceDetection()
                startLongDictationWarning()
            } catch {
                self.error = "Failed to start recording: \(error.localizedDescription)"
                self.state = .idle
                self.liveTextCancellable = nil
            }
        }
    }

    func stopDictation() {
        guard state.isActive else { return }

        silenceCancellable = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        longDictationTimer?.invalidate()
        longDictationTimer = nil
        liveTextCancellable = nil

        state = .transcribing

        Task {
            audioEngine.stopCapturing()
            let rawText = await streamingTranscriber.stopStreaming()
            liveText = ""

            if settingsStore.playStartStopSounds {
                NSSound(named: "Pop")?.play()
            }

            guard !rawText.isEmpty else {
                sessionStartTime = nil
                state = .idle
                return
            }

            // Process through pipeline
            state = .processing
            let result = await textPipeline.process(rawText)

            // Handle voice commands
            if let command = result.command {
                if command == .stopListening {
                    logTranscription(rawText: rawText, processedText: "", wasVoiceCommand: true, voiceCommandName: command.logName)
                    sessionStartTime = nil
                    state = .idle
                    return
                }

                // Inject any remaining text first
                if !result.text.isEmpty {
                    state = .injecting
                    await textInjector.inject(result.text)
                    lastTranscription = result.text
                }

                state = .executingCommand
                await commandExecutor.execute(command)
                logTranscription(rawText: rawText, processedText: result.text, wasVoiceCommand: true, voiceCommandName: command.logName)
                sessionStartTime = nil
                state = .idle
                return
            }

            // Inject text
            if !result.text.isEmpty {
                state = .injecting
                await textInjector.inject(result.text)
                lastTranscription = result.text
            }

            logTranscription(rawText: rawText, processedText: result.text, wasVoiceCommand: false, voiceCommandName: nil)
            sessionStartTime = nil
            state = .idle
        }
    }

    private func logTranscription(rawText: String, processedText: String, wasVoiceCommand: Bool, voiceCommandName: String?) {
        let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let entry = TranscriptionLog(
            duration: duration,
            text: processedText,
            rawText: rawText,
            modelUsed: settingsStore.selectedModelName,
            wasVoiceCommand: wasVoiceCommand,
            voiceCommandName: voiceCommandName
        )
        transcriptionLogStore.log(entry)
    }

    private func startSilenceDetection() {
        let timeout = settingsStore.silenceTimeoutSeconds
        let silenceThreshold: Float = 0.05

        // When audio level drops below threshold, start a timer.
        // When it goes above threshold, cancel the timer.
        // If the timer fires (silence lasted longer than timeout), stop dictation.
        silenceCancellable = audioEngine.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, self.state == .listening else { return }
                if level < silenceThreshold {
                    // Below threshold — start timer if not already running
                    if self.silenceTimer == nil {
                        self.silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, self.state == .listening else { return }
                                self.stopDictation()
                            }
                        }
                    }
                } else {
                    // Above threshold — reset timer
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = nil
                }
            }
    }

    private func startLongDictationWarning() {
        longDictationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                self.error = "Still recording — long sessions may reduce accuracy"
            }
        }
    }
}
