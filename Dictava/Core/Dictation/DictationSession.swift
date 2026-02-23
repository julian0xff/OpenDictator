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
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?

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

        // Clear microphone error when permission is granted
        PermissionManager.shared.$microphoneStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, status == .granted else { return }
                if self.error == "Microphone permission not granted" {
                    self.error = nil
                }
            }
            .store(in: &cancellables)

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
        modelLoadTask = Task {
            try? await transcriptionEngine.loadModel(named: settingsStore.selectedModelName)
            modelLoadTask = nil
        }
        await modelLoadTask?.value
    }

    func switchModel(to modelName: String) {
        guard modelName != settingsStore.selectedModelName || !transcriptionEngine.isModelLoaded else { return }

        let isDownloaded = modelManager.availableModels.first(where: { $0.name == modelName })?.isDownloaded ?? false
        settingsStore.selectedModelName = modelName

        guard isDownloaded else { return }  // Don't unload current model if target isn't ready

        modelLoadTask?.cancel()
        transcriptionEngine.unloadModel()
        modelLoadTask = Task {
            try? await transcriptionEngine.loadModel(named: modelName)
            modelLoadTask = nil
        }
    }

    func switchLanguage(to languageCode: String) {
        settingsStore.selectedLanguage = languageCode

        let currentTier = modelManager.tier(for: settingsStore.selectedModelName)
        let candidates = modelManager.models(for: languageCode)

        // 1. Try same tier, downloaded
        if let sameTier = candidates.first(where: { $0.tier == currentTier && $0.isDownloaded }) {
            if sameTier.name != settingsStore.selectedModelName {
                switchModel(to: sameTier.name)
            }
            return
        }

        // 2. Fall back to smallest downloaded model for new language
        if let fallback = modelManager.bestDownloadedModel(for: languageCode) {
            if fallback != settingsStore.selectedModelName {
                switchModel(to: fallback)
            }
            return
        }

        // 3. Nothing downloaded for this language — update setting only
        let newModelName = modelManager.bestModel(tier: currentTier, for: languageCode)
        settingsStore.selectedModelName = newModelName
    }

    func toggle() {
        if state == .idle {
            startDictation()
        } else if state == .listening {
            stopDictation()
        } else {
            // Pressed hotkey while transcribing/processing/injecting — cancel and reset
            cancelStop()
        }
    }

    private func cancelStop() {
        startTask?.cancel()
        startTask = nil
        stopTask?.cancel()
        stopTask = nil
        audioEngine.stopCapturing()
        liveText = ""
        liveTextCancellable = nil
        sessionStartTime = nil
        state = .idle
    }

    func startDictation() {
        guard state == .idle else { return }

        error = nil
        liveText = ""

        guard PermissionManager.shared.microphoneStatus == .granted else {
            error = "Microphone permission not granted"
            return
        }

        sessionStartTime = Date()

        // Subscribe to live text for this session
        liveTextCancellable = streamingTranscriber.$liveText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.liveText = text
            }

        // Check if model is ready right now
        let modelReady = modelLoadTask == nil
            && transcriptionEngine.isModelLoaded
            && transcriptionEngine.loadedModelName == settingsStore.selectedModelName

        state = modelReady ? .listening : .loadingModel

        startTask = Task {
            // Wait for any in-progress model load (e.g. from switchModel)
            if let loadTask = modelLoadTask {
                await loadTask.value
            }
            guard !Task.isCancelled else { cleanup(); return }

            // Ensure correct model is loaded
            let needsLoad = !transcriptionEngine.isModelLoaded
                || transcriptionEngine.loadedModelName != settingsStore.selectedModelName
            if needsLoad {
                if transcriptionEngine.isModelLoaded {
                    transcriptionEngine.unloadModel()
                }
                do {
                    try await transcriptionEngine.loadModel(named: settingsStore.selectedModelName)
                } catch {
                    self.error = "Failed to load model: \(error.localizedDescription)"
                    cleanup()
                    return
                }
            }
            guard !Task.isCancelled else { cleanup(); return }

            // Model ready — transition to listening and start audio
            state = .listening

            do {
                try audioEngine.startCapturing()
                streamingTranscriber.startStreaming(from: audioEngine, language: settingsStore.selectedLanguage)

                if settingsStore.playStartStopSounds {
                    NSSound(named: "Tink")?.play()
                }

                startSilenceDetection()
                startLongDictationWarning()
            } catch {
                self.error = "Failed to start recording: \(error.localizedDescription)"
                cleanup()
            }
            startTask = nil
        }
    }

    private func cleanup() {
        state = .idle
        liveTextCancellable = nil
        sessionStartTime = nil
    }

    func stopDictation() {
        guard state == .listening else { return }

        silenceCancellable = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        longDictationTimer?.invalidate()
        longDictationTimer = nil
        liveTextCancellable = nil
        error = nil

        state = .transcribing

        stopTask = Task {
            audioEngine.stopCapturing()
            let rawText = await streamingTranscriber.stopStreaming()
            liveText = ""

            guard !Task.isCancelled else { return }

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

            guard !Task.isCancelled else { return }

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

                guard !Task.isCancelled else { return }

                state = .executingCommand
                await commandExecutor.execute(command)
                logTranscription(rawText: rawText, processedText: result.text, wasVoiceCommand: true, voiceCommandName: command.logName)
                sessionStartTime = nil
                state = .idle
                return
            }

            // Inject text
            guard !Task.isCancelled else { return }

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
