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
    @Published var activeProviderDisplayName: String = ""

    private var sessionStartTime: Date?

    private let audioEngine = AudioCaptureEngine()
    private let transcriptionEngine = TranscriptionEngine()
    private lazy var streamingTranscriber = StreamingTranscriber(transcriptionEngine: transcriptionEngine)
    private let textInjector = TextInjector()
    private let commandExecutor = VoiceCommandExecutor()
    private let textPipeline: TextPipeline

    private let whisperKitProvider = WhisperKitProvider()
    private let fluidAudioProvider = FluidAudioProvider()

    private let settingsStore: SettingsStore
    private let modelManager: ModelManager
    private let fluidAudioModelManager: FluidAudioModelManager
    private let transcriptionLogStore: TranscriptionLogStore

    private var cancellables = Set<AnyCancellable>()
    private var liveTextCancellable: AnyCancellable?
    private var silenceCancellable: AnyCancellable?
    private var silenceTimer: Timer?
    private var longDictationTimer: Timer?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?

    init(settingsStore: SettingsStore, modelManager: ModelManager, fluidAudioModelManager: FluidAudioModelManager, snippetStore: SnippetStore, vocabularyStore: VocabularyStore, transcriptionLogStore: TranscriptionLogStore) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.fluidAudioModelManager = fluidAudioModelManager
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

        // Wire up cross-references for FluidAudio model management
        fluidAudioModelManager.fluidAudioProvider = fluidAudioProvider
        fluidAudioProvider.fluidAudioModelManager = fluidAudioModelManager

        // Set provider based on language preference
        let provider = providerInstance(for: settingsStore.preferredProvider(for: settingsStore.selectedLanguage))
        transcriptionEngine.setProvider(provider)
        updateProviderDisplayName()

        // Sync transcription engine state when FluidAudio model is downloaded or deleted
        fluidAudioModelManager.$isDownloaded
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isDownloaded in
                guard let self else { return }
                if !isDownloaded {
                    // Model was deleted — sync transcription engine state so it doesn't think model is still loaded
                    if self.transcriptionEngine.activeProviderID == .fluidAudio {
                        self.transcriptionEngine.unloadModel()
                    }
                } else if self.state == .idle {
                    // Model was downloaded — auto-preload if FluidAudio is active
                    self.error = nil
                    let preferred = self.settingsStore.preferredProvider(for: self.settingsStore.selectedLanguage)
                    if preferred == .fluidAudio && self.transcriptionEngine.activeProviderID == .fluidAudio {
                        self.modelLoadTask = Task {
                            do {
                                try await self.transcriptionEngine.loadModel(named: nil)
                            } catch {
                                self.error = "Failed to load Parakeet model: \(error.localizedDescription)"
                            }
                            self.updateProviderDisplayName()
                            self.modelLoadTask = nil
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Clear stale "model not downloaded" error when download starts
        fluidAudioModelManager.$isDownloading
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.error?.contains("not downloaded") == true {
                    self.error = nil
                }
            }
            .store(in: &cancellables)
    }

    private func providerInstance(for id: ASRProviderID) -> ASRProvider {
        switch id {
        case .whisperKit: return whisperKitProvider
        case .fluidAudio: return fluidAudioProvider
        }
    }

    func switchProvider(to providerID: ASRProviderID, modelName: String? = nil) {
        guard state == .idle else { return }

        modelLoadTask?.cancel()

        // Bug 9: Capture old provider to clear its stale buffer
        let oldProvider = transcriptionEngine.activeProviderID.map { providerInstance(for: $0) }

        transcriptionEngine.unloadModel()

        let provider = providerInstance(for: providerID)
        transcriptionEngine.setProvider(provider)
        updateProviderDisplayName()

        // Don't attempt to load FluidAudio if model isn't downloaded — avoid silent background download
        if providerID == .fluidAudio && !fluidAudioModelManager.isDownloaded {
            return
        }

        let name: String? = providerID == .whisperKit ? (modelName ?? settingsStore.selectedModelName) : nil

        modelLoadTask = Task {
            // Clear old provider's stale audio buffer before loading new model
            await oldProvider?.reset()
            try? await transcriptionEngine.loadModel(named: name)
            updateProviderDisplayName()
            modelLoadTask = nil
        }
    }

    func preloadModel() async {
        guard !transcriptionEngine.isModelLoaded else { return }

        // Ensure the correct provider is set
        let preferred = settingsStore.preferredProvider(for: settingsStore.selectedLanguage)
        if transcriptionEngine.activeProviderID != preferred {
            let provider = providerInstance(for: preferred)
            transcriptionEngine.setProvider(provider)
        }

        // Don't silently download FluidAudio — require explicit download via Settings
        if preferred == .fluidAudio && !fluidAudioModelManager.isDownloaded {
            return
        }

        let modelName: String? = preferred == .whisperKit ? settingsStore.selectedModelName : nil
        modelLoadTask = Task {
            try? await transcriptionEngine.loadModel(named: modelName)
            updateProviderDisplayName()
            modelLoadTask = nil
        }
        await modelLoadTask?.value
    }

    func switchModel(to modelName: String) {
        guard modelName != settingsStore.selectedModelName || !transcriptionEngine.isModelLoaded else { return }

        let isDownloaded = modelManager.availableModels.first(where: { $0.name == modelName })?.isDownloaded ?? false
        settingsStore.selectedModelName = modelName
        updateProviderDisplayName()

        guard isDownloaded else { return }  // Don't unload current model if target isn't ready

        modelLoadTask?.cancel()
        transcriptionEngine.unloadModel()
        modelLoadTask = Task {
            try? await transcriptionEngine.loadModel(named: modelName)
            updateProviderDisplayName()
            modelLoadTask = nil
        }
    }

    func switchLanguage(to languageCode: String) {
        guard state == .idle else { return }

        settingsStore.selectedLanguage = languageCode

        // Check if preferred provider for this language differs from active
        let preferred = settingsStore.preferredProvider(for: languageCode)
        if preferred != transcriptionEngine.activeProviderID {
            // Compute the right WhisperKit model name BEFORE switching provider
            var modelName: String? = nil
            if preferred == .whisperKit {
                let currentTier = modelManager.tier(for: settingsStore.selectedModelName)
                if let downloaded = modelManager.bestDownloadedModel(for: languageCode) {
                    modelName = downloaded
                } else {
                    modelName = modelManager.bestModel(tier: currentTier, for: languageCode)
                }
                settingsStore.selectedModelName = modelName!
            }
            switchProvider(to: preferred, modelName: modelName)
            return
        }

        // Same provider — if WhisperKit, handle model selection
        if preferred == .whisperKit {
            let currentTier = modelManager.tier(for: settingsStore.selectedModelName)
            let candidates = modelManager.models(for: languageCode)

            if let sameTier = candidates.first(where: { $0.tier == currentTier && $0.isDownloaded }) {
                if sameTier.name != settingsStore.selectedModelName {
                    switchModel(to: sameTier.name)
                }
                return
            }

            if let fallback = modelManager.bestDownloadedModel(for: languageCode) {
                if fallback != settingsStore.selectedModelName {
                    switchModel(to: fallback)
                }
                return
            }

            let newModelName = modelManager.bestModel(tier: currentTier, for: languageCode)
            settingsStore.selectedModelName = newModelName
        }
        // FluidAudio staying on FluidAudio — no model switch needed
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
        streamingTranscriber.cancelStreaming()
        liveText = ""
        audioLevelHistory = Array(repeating: 0, count: 20)
        liveTextCancellable = nil
        sessionStartTime = nil
        state = .idle
    }

    func startDictation() {
        guard state == .idle else { return }

        error = nil
        liveText = ""
        audioLevelHistory = Array(repeating: 0, count: 20)

        guard PermissionManager.shared.microphoneStatus == .granted else {
            error = "Microphone permission not granted"
            return
        }

        if transcriptionEngine.activeProviderID == .fluidAudio && !fluidAudioModelManager.isDownloaded {
            error = "Parakeet model not downloaded. Download it in Settings → Speech Recognition."
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
        let isFluidAudio = transcriptionEngine.activeProviderID == .fluidAudio
        let modelReady: Bool
        if isFluidAudio {
            modelReady = modelLoadTask == nil && transcriptionEngine.isModelLoaded
        } else {
            modelReady = modelLoadTask == nil
                && transcriptionEngine.isModelLoaded
                && transcriptionEngine.loadedModelName == settingsStore.selectedModelName
        }

        state = modelReady ? .listening : .loadingModel

        startTask = Task {
            // Wait for any in-progress model load (e.g. from switchModel)
            if let loadTask = modelLoadTask {
                await loadTask.value
            }
            guard !Task.isCancelled else { cleanup(); return }

            // Ensure correct model is loaded
            let needsLoad: Bool
            if transcriptionEngine.activeProviderID == .fluidAudio {
                needsLoad = !transcriptionEngine.isModelLoaded
            } else {
                needsLoad = !transcriptionEngine.isModelLoaded
                    || transcriptionEngine.loadedModelName != settingsStore.selectedModelName
            }
            if needsLoad {
                if transcriptionEngine.isModelLoaded {
                    transcriptionEngine.unloadModel()
                }
                do {
                    let modelName: String? = transcriptionEngine.activeProviderID == .fluidAudio
                        ? nil : settingsStore.selectedModelName
                    try await transcriptionEngine.loadModel(named: modelName)
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
                await streamingTranscriber.startStreaming(from: audioEngine, language: settingsStore.selectedLanguage)

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
            let rawText = await streamingTranscriber.stopStreaming()
            audioEngine.stopCapturing()
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

    private func updateProviderDisplayName() {
        if transcriptionEngine.activeProviderID == .fluidAudio {
            activeProviderDisplayName = "Parakeet v3"
        } else {
            activeProviderDisplayName = modelManager.availableModels
                .first(where: { $0.name == settingsStore.selectedModelName })?
                .displayName ?? settingsStore.selectedModelName
        }
    }

    private func logTranscription(rawText: String, processedText: String, wasVoiceCommand: Bool, voiceCommandName: String?) {
        let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let modelName = transcriptionEngine.activeProviderID == .fluidAudio
            ? "parakeet-v3" : settingsStore.selectedModelName
        let entry = TranscriptionLog(
            duration: duration,
            text: processedText,
            rawText: rawText,
            modelUsed: modelName,
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
