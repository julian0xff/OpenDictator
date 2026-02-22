# Dictava

A macOS menu bar dictation app that uses WhisperKit for local, on-device speech-to-text transcription. All processing happens locally — no data leaves the Mac. Works completely offline after initial model download.

## Architecture

**App type:** Menu bar only (`LSUIElement = true`) — no dock icon, no main window. Lives in the system tray with a popover for status and a floating indicator during dictation.

**Entry point:** `DictavaApp.swift` uses `@NSApplicationDelegateAdaptor` → `AppDelegate.swift` owns all state objects and wires up the status bar controller, floating indicator, and global hotkey.

### Core Objects (all created in AppDelegate)

| Object | Role |
|--------|------|
| `DictationSession` | Central orchestrator — manages state machine (idle → listening → transcribing → processing → injecting → idle), audio capture, streaming transcription, text pipeline, text injection, and transcription logging |
| `SettingsStore` | `@AppStorage`-backed preferences, including voice command enabled/disabled state, audio settings, UI preferences |
| `ModelManager` | Downloads, lists, deletes WhisperKit CoreML models |
| `SnippetStore` | User-defined text snippets (YAML-backed) with template variable support (`{{date}}`, `{{time}}`, `{{clipboard}}`) |
| `VocabularyStore` | Custom vocabulary entries for word corrections (JSON-backed) |
| `TranscriptionLogStore` | Persists all dictation history with metadata — duration, raw/processed text, model used, voice command status (JSON-backed) |

### Dictation Flow

1. User presses **Option+Space** (global hotkey via `KeyboardShortcuts` package)
2. `DictationSession.toggle()` → `startDictation()`
3. `AudioCaptureEngine` starts capturing mic input via `AVAudioEngine`
4. `StreamingTranscriber` feeds audio chunks to `TranscriptionEngine` (WhisperKit)
5. `TranscriptionEngine` strips non-speech artifacts before returning text
6. Live partial transcripts update `DictationSession.liveText` every 1.5 seconds
7. On stop (manual or silence detection): final transcription → `TextPipeline` processing → `TextInjector` types text at cursor via CGEvents
8. Session logged to `TranscriptionLogStore` with full metadata (duration, raw/processed text, model, voice command status)
9. Floating indicator (`DictationIndicatorWindow`) shows state throughout with audio waveform visualization

### Text Pipeline

Sequential processors in `TextPipeline`:
1. `VoiceCommandParser` — detects commands like "select all", "new line", "stop listening". Respects per-command enabled/disabled state from `SettingsStore`
2. `PunctuationHandler` — converts spoken punctuation ("period", "comma") to symbols
3. `SnippetExpander` — expands user-defined abbreviations
4. `FillerWordFilter` — removes "um", "uh", "like", etc.
5. `CustomVocabulary` — applies user-defined word corrections
6. `LLMProcessor` — optional AI cleanup (currently placeholder)

### Non-Speech Artifact Filtering

`TranscriptionEngine.stripNonSpeechAnnotations()` runs on all transcription output (both partial and final) before it reaches the text pipeline. Removes:
- Bracketed annotations: `[Silence]`, `[clears throat]`, `[BLANK_AUDIO]`, `[music]`, `[laughter]`, etc.
- Parenthesized annotations: `(silence)`, `(inaudible)`, `(speaking foreign language)`, etc.
- Music symbols: `♪`, `♫`, `♬`, `♩`, `♭`, `♮`, `♯`

These are hallucinated by Whisper from its YouTube subtitle training data when it receives silence or non-speech audio. The filter uses regex to catch any `[...]` or `(...)` pattern — real speech never produces bracketed text.

### UI Layer

- **`StatusBarController`** — NSPopover from menu bar icon, shows dictation status and audio level
- **`DictationIndicatorWindow`** — Floating NSPanel (capsule shape, `.ultraThinMaterial` with white border outline), shows pulsing red dot + audio waveform during listening, spinner during processing
- **`SettingsView`** — macOS System Settings-style `NavigationSplitView` with sidebar (General, Speech Recognition, Text Processing, Snippets, Commands, History, Advanced)
- **`HistoryView`** — Dashboard with stats cards (today count, listening time, all-time count), 14-day bar chart (Charts framework), searchable/filterable transcription log with expandable details
- **`SnippetSettingsView`** — Full CRUD for snippets: add, edit (pencil button), delete (trash button) with sheet editor
- **`VoiceCommandSettingsView`** — Toggle switches to enable/disable individual voice commands, reads definitions from `VoiceCommandParser.allDefinitions`
- **`OnboardingView`** — First-launch setup wizard

## Project Structure

```
Dictava/
├── AppDelegate.swift              # App lifecycle, state object creation
├── DictavaApp.swift               # SwiftUI App, Settings scene
├── Core/
│   ├── Audio/
│   │   └── AudioCaptureEngine.swift    # AVAudioEngine mic capture
│   ├── Dictation/
│   │   ├── DictationSession.swift      # Main orchestrator
│   │   ├── DictationState.swift        # State enum
│   │   └── VoiceCommandExecutor.swift  # Executes parsed commands
│   ├── TextInjection/
│   │   ├── TextInjector.swift          # CGEvent-based typing
│   │   └── SyntheticEventMarker.swift  # Marks synthetic events
│   ├── TextProcessing/
│   │   ├── TextPipeline.swift          # Sequential processor chain
│   │   ├── VoiceCommandParser.swift    # Command definitions + per-command enable/disable
│   │   ├── PunctuationHandler.swift
│   │   ├── SnippetExpander.swift
│   │   ├── FillerWordFilter.swift
│   │   ├── CustomVocabulary.swift
│   │   └── LLMProcessor.swift
│   └── Transcription/
│       ├── ModelManager.swift          # WhisperKit model management
│       ├── StreamingTranscriber.swift  # Chunked streaming transcription
│       └── TranscriptionEngine.swift   # WhisperKit wrapper + non-speech filtering
├── Services/
│   ├── HotkeyManager.swift            # KeyboardShortcuts names
│   └── PermissionManager.swift        # Mic + Accessibility status polling
├── Storage/
│   ├── SettingsStore.swift             # @AppStorage preferences + voice command state
│   ├── SnippetStore.swift              # YAML-backed snippets
│   ├── VocabularyStore.swift           # JSON-backed vocabulary
│   ├── TranscriptionLog.swift          # Data structure for single log entry
│   └── TranscriptionLogStore.swift     # JSON persistence + analytics queries
├── UI/
│   ├── MenuBar/
│   │   ├── StatusBarController.swift        # Menu bar popover
│   │   └── DictationIndicatorWindow.swift   # Floating pill indicator
│   ├── History/
│   │   └── HistoryView.swift               # Stats, charts, searchable log
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   └── Settings/
│       ├── SettingsView.swift                # NavigationSplitView sidebar
│       ├── GeneralSettingsView.swift         # Hotkey, behavior, permissions
│       ├── SpeechRecognitionSettingsView.swift # Model selection, silence
│       ├── TextProcessingSettingsView.swift  # Corrections, vocabulary, AI
│       ├── SnippetSettingsView.swift         # Add, edit, delete snippets
│       ├── VoiceCommandSettingsView.swift    # Enable/disable voice commands
│       └── AdvancedSettingsView.swift
└── Resources/
    ├── Assets.xcassets/                # App icon
    ├── Info.plist
    └── Dictava.entitlements
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | >= 0.9.0 | Local speech-to-text via CoreML |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | >= 2.0.0 | Global hotkey recording & handling |
| [Yams](https://github.com/jpsim/Yams) | >= 5.0.0 | YAML parsing for snippets |

Also uses Apple's **Charts** framework (built-in) for the history dashboard bar chart.

## Build

```bash
# Generate project (if needed)
xcodegen generate

# Build production app
xcodebuild -project Dictava.xcodeproj -scheme Dictava -destination 'platform=macOS,arch=arm64' build

# Build dev app (can run side-by-side with production)
xcodebuild -project Dictava.xcodeproj -scheme DictavaDev -destination 'platform=macOS,arch=arm64' build
```

**Requirements:** macOS 13.0+, Apple Silicon (arm64 only), Xcode 15+

### Build Targets

| Target | Bundle ID | Purpose |
|--------|-----------|---------|
| `Dictava` | `com.dictava.app` | Production build |
| `DictavaDev` | `com.dictava.app.dev` | Dev build — separate app, separate permissions, runs alongside production |

**Note:** Both targets register the same Option+Space hotkey, so only run one at a time.

### Deploying to /Applications

```bash
# Quit running app, replace, relaunch
osascript -e 'quit app "Dictava"'; sleep 1
rm -rf /Applications/Dictava.app
cp -R ~/Library/Developer/Xcode/DerivedData/Dictava-*/Build/Products/Debug/Dictava.app /Applications/Dictava.app
open /Applications/Dictava.app
```

**Important:** Use `rm -rf` then `cp -R`, not just `cp -R` over an existing `.app` bundle. macOS merges rather than replaces, leaving stale binaries.

## Key Implementation Details

- **Fully offline:** Everything runs on-device after initial model download. No API calls, no network required
- **WhisperKit model storage:** Models download to `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/` (not `~/Library/Application Support/`)
- **Model preloading:** The selected Whisper model loads at app launch (`AppDelegate.preloadModel()`) to avoid delay on first dictation
- **Model switching:** `DictationSession.switchModel(to:)` unloads current model and loads new one in background
- **Race condition prevention:** `state = .listening` is set synchronously before the async Task in `startDictation()` to prevent re-entry from rapid hotkey presses
- **Live text subscription:** Created per-session in `startDictation()` and cancelled in `stopDictation()` to ensure it works across multiple sessions
- **Partial transcription:** Triggered every 1.5 seconds by timer in `StreamingTranscriber` for real-time preview
- **Silence detection:** Uses audio level threshold (0.05 normalized), starts timer when below, resets when above
- **Audio level calculation:** RMS normalization over sample frames with dB scaling (-50dB to 0dB → 0 to 1 range)
- **Permissions polling:** `PermissionManager` polls every 2 seconds for accessibility status changes (no system notification exists for this)
- **Text injection:** Uses `CGEvent` to synthesize keystrokes — requires Accessibility permission. 50ms delay before Cmd+V, 200ms wait after
- **Dock icon policy:** Dynamically toggles `NSApplication.setActivationPolicy()` based on `showDockIcon` setting and whether windows are open
- **Transcription logging:** Every session logged with duration, raw text, processed text, model used, and voice command metadata
- **LSUIElement focus:** Settings window calls `NSApp.activate(ignoringOtherApps: true)` on appear since menu bar apps don't auto-activate
- **Floating indicator:** `NSPanel` with `.borderless` + `.nonactivatingPanel` — doesn't steal focus from the active app. Has a subtle white border (`0.25` opacity, `1px`) for visibility on dark backgrounds
- **Non-speech filtering:** `TranscriptionEngine` strips `[...]`, `(...)`, and music symbols via regex before returning text. Catches all Whisper hallucination artifacts without needing a hardcoded list
- **Voice command toggles:** Disabled commands stored as comma-separated names in `SettingsStore.disabledVoiceCommands`. `VoiceCommandParser` skips disabled commands during processing
- **Voice command definitions:** Centralized in `VoiceCommandParser.allDefinitions` (static array), used by both the parser and the settings UI

## Versioning & Releases

Uses semantic versioning (MAJOR.MINOR.PATCH):
- **PATCH** — bug fixes only
- **MINOR** — new features, backwards compatible
- **MAJOR** — breaking changes or "production-ready" milestone

### Release Process

To create a new release:

```bash
./scripts/release.sh 0.3.0
```

This script:
1. Validates semver format and checks clean main branch
2. Updates `MARKETING_VERSION` in `project.yml` (both targets)
3. Commits the version bump
4. Creates annotated git tag `v0.3.0`
5. Pushes commit + tag to origin

The tag push triggers `.github/workflows/release.yml` which:
1. Builds the app on Apple Silicon CI (`macos-14`)
2. Creates a DMG (`Dictava-0.3.0.dmg`)
3. Publishes a GitHub Release with the DMG attached
4. Triggers the Homebrew tap update at `julian0xff/homebrew-tap`

### Distribution

- **GitHub Releases:** DMG download at `github.com/julian0xff/Dictava/releases`
- **Homebrew:** `brew install --cask julian0xff/tap/dictava` (tap repo: `julian0xff/homebrew-tap`)
- **Build from source:** `xcodegen generate && xcodebuild ...`

### CI Secrets

- `GITHUB_TOKEN` — auto-provided, used for creating GitHub Releases
- `TAP_UPDATE_TOKEN` — PAT with `repo` + `workflow` scopes, used to trigger the Homebrew tap update workflow

## Hotkeys

| Action | Hotkey | Notes |
|--------|--------|-------|
| Toggle dictation | Option+Space | Editable via Settings → General |
| Copy last transcription | Option+Shift+Space | Fixed, copies to clipboard |

## Data Storage

| Data | Location | Format |
|------|----------|--------|
| Preferences | `~/Library/Preferences/com.dictava.app.plist` | UserDefaults |
| Snippets | `~/Library/Application Support/Dictava/snippets.yml` | YAML |
| Custom vocabulary | `~/Library/Application Support/Dictava/vocabulary.json` | JSON |
| Transcription history | `~/Library/Application Support/Dictava/transcription_logs.json` | JSON |
| Whisper models | `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/` | CoreML |

## Platform Constraints

- **Apple Silicon only** — `EXCLUDED_ARCHS[sdk=macosx*]: x86_64` in project.yml
- **Intel Mac support** would only require removing the arch exclusion (all APIs support x86_64, WhisperKit runs on CPU/GPU without Neural Engine)
- **Linux is not feasible** — requires full rewrite due to AppKit, AVFoundation, CGEvent, CoreML dependencies. Only the text processing pipeline and YAML stores are portable
