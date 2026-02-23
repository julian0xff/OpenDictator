# Dictava

A macOS menu bar dictation app with multi-provider local speech-to-text. Supports **NVIDIA Parakeet** (FluidAudio SDK, recommended for 25 European languages) and **WhisperKit** (OpenAI Whisper models, 100+ languages). All processing happens locally — no data leaves the Mac. Works completely offline after initial model download.

## Architecture

**App type:** Menu bar only (`LSUIElement = true`) — no dock icon, no main window. Lives in the system tray with a popover for status and a floating indicator during dictation.

**Entry point:** `DictavaApp.swift` uses `@NSApplicationDelegateAdaptor` → `AppDelegate.swift` owns all state objects and wires up the status bar controller, floating indicator, and global hotkey.

**Settings window:** Managed as a custom `NSWindow` + `NSHostingController` (not a SwiftUI `Settings` scene — that scene strips `.resizable` from the window). `AppDelegate.openSettingsWindow()` creates/reuses the window. The `DictavaApp.swift` `Settings` scene contains `EmptyView()` with a `CommandGroup(replacing: .appSettings)` that redirects Cmd+, to the custom window. The popover's Settings button uses `NSApp.sendAction(#selector(AppDelegate.openSettingsWindow))` to avoid `@MainActor` isolation issues.

### Core Objects (all created in AppDelegate)

| Object | Role |
|--------|------|
| `DictationSession` | Central orchestrator — manages state machine (idle → loadingModel → listening → transcribing → processing → injecting → idle), audio capture, streaming transcription, text pipeline, text injection, and transcription logging. Owns both `WhisperKitProvider` and `FluidAudioProvider` instances |
| `SettingsStore` | `@AppStorage`-backed preferences, including voice command enabled/disabled state, audio settings, UI preferences, indicator theme selection, per-language provider overrides |
| `ModelManager` | Downloads, lists, deletes WhisperKit CoreML models |
| `FluidAudioModelManager` | Downloads, caches, deletes NVIDIA Parakeet v3 model. Publishes `downloadProgress` via file-system polling. Auto-triggers model preload in `DictationSession` when download completes |
| `SnippetStore` | User-defined text snippets (YAML-backed) with template variable support (`{{date}}`, `{{time}}`, `{{clipboard}}`) |
| `VocabularyStore` | Custom vocabulary entries for word corrections (JSON-backed) |
| `TranscriptionLogStore` | Persists all dictation history with metadata — duration, raw/processed text, model used, voice command status (JSON-backed) |
| `CustomThemeStore` | User-defined indicator themes (JSON-backed) |

### Dictation Flow

1. User presses **Option+Space** (global hotkey via `KeyboardShortcuts` package)
2. `DictationSession.toggle()` → `startDictation()`
3. If model not loaded: state → `.loadingModel`, floating indicator shows spinner + "Loading model..."
4. Model loads (or awaits in-progress `modelLoadTask` from `switchModel`), then state → `.listening`
5. `AudioCaptureEngine` starts capturing mic input via `AVAudioEngine`
6. `StreamingTranscriber` feeds audio chunks to `TranscriptionEngine` via the active `ASRProvider` (Parakeet or WhisperKit)
7. `TranscriptionEngine` delegates to the provider for transcription; WhisperKit results are stripped of non-speech artifacts
8. Live partial transcripts update `DictationSession.liveText` every 1.5 seconds
9. On stop (manual or silence detection): final transcription → `TextPipeline` processing → `TextInjector` types text at cursor via CGEvents
10. Session logged to `TranscriptionLogStore` with full metadata (duration, raw/processed text, model, voice command status)
11. Floating indicator (`DictationIndicatorWindow`) shows state throughout with themed audio waveform visualization

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

- **`StatusBarController`** — NSPopover from menu bar icon with structured sections: header (app name + state), body (error banner, audio bar, live text, action button), recent transcriptions (hover-to-copy), and footer (Settings + Quit buttons with hover styles)
- **`DictationIndicatorWindow`** — Floating NSPanel (themed capsule shape), shows audio waveform during listening, spinner during processing. Theme-aware colors for background, border, text, and waveform. Respects `showFloatingIndicator` setting. Auto-resizes to fit content
- **`SettingsView`** — HStack-based layout with fixed 220px sidebar (List with PhosphorSwift icons) and detail pane. Sidebar cannot be hidden or resized. Tabs: General, Appearance, Speech Recognition, Text Processing, Snippets, Commands, History, Advanced
- **`AppearanceSettingsView`** — Indicator theme selection with built-in themes (System, Dark, Light) and custom theme support
- **`HistoryView`** — Dashboard with stats cards (today count, listening time, all-time count), 14-day bar chart (Charts framework), searchable/filterable transcription log with expandable details
- **`SnippetSettingsView`** — Full CRUD for snippets: add, edit (pencil button), delete (trash button) with sheet editor
- **`VoiceCommandSettingsView`** — Toggle switches to enable/disable individual voice commands, reads definitions from `VoiceCommandParser.allDefinitions`
- **`OnboardingView`** — First-launch setup wizard

## Project Structure

```
Dictava/
├── AppDelegate.swift              # App lifecycle, state object creation, settings window
├── DictavaApp.swift               # SwiftUI App, empty Settings scene + Cmd+, override
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
│       ├── ASRProvider.swift           # Provider protocol (loadModel, transcribe, reset, flush)
│       ├── AudioSampleBuffer.swift     # Actor-isolated thread-safe sample buffer
│       ├── FluidAudioModelManager.swift # Parakeet model download, progress polling, lifecycle
│       ├── FluidAudioProvider.swift    # NVIDIA Parakeet ASR provider
│       ├── ModelManager.swift          # WhisperKit model management
│       ├── ProviderCatalog.swift       # Provider selection: Parakeet recommended for 25 langs
│       ├── StreamingTranscriber.swift  # Chunked streaming transcription + partial timer
│       ├── SupportedLanguage.swift     # Language model + 100 Whisper-supported languages
│       ├── TranscriptionEngine.swift   # Provider-agnostic transcription engine + flight guards
│       └── WhisperKitProvider.swift    # WhisperKit ASR provider + non-speech filtering
├── Services/
│   ├── HotkeyManager.swift            # KeyboardShortcuts names
│   └── PermissionManager.swift        # Mic + Accessibility status polling
├── Storage/
│   ├── SettingsStore.swift             # @AppStorage preferences + voice command state + theme
│   ├── SnippetStore.swift              # YAML-backed snippets
│   ├── VocabularyStore.swift           # JSON-backed vocabulary
│   ├── CustomThemeStore.swift          # JSON-backed custom indicator themes
│   ├── IndicatorTheme.swift            # Theme model + built-in themes
│   ├── TranscriptionLog.swift          # Data structure for single log entry
│   └── TranscriptionLogStore.swift     # JSON persistence + analytics queries
├── UI/
│   ├── MenuBar/
│   │   ├── StatusBarController.swift        # Menu bar popover (sections: header, body, recent, footer)
│   │   └── DictationIndicatorWindow.swift   # Floating themed pill indicator
│   ├── History/
│   │   └── HistoryView.swift               # Stats, charts, searchable log
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   └── Settings/
│       ├── SettingsView.swift                # HStack sidebar + detail pane
│       ├── GeneralSettingsView.swift         # Hotkey, behavior, permissions
│       ├── AppearanceSettingsView.swift      # Indicator theme picker
│       ├── SpeechRecognitionSettingsView.swift # Model selection, silence
│       ├── TextProcessingSettingsView.swift  # Corrections, vocabulary, AI
│       ├── SnippetSettingsView.swift         # Add, edit, delete snippets
│       ├── VoiceCommandSettingsView.swift    # Enable/disable voice commands
│       ├── AdvancedSettingsView.swift
│       └── HistoryView.swift (in History/)
└── Resources/
    ├── Assets.xcassets/                # App icon
    ├── Info.plist
    └── Dictava.entitlements
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | >= 0.9.0 | Local speech-to-text via CoreML (100+ languages) |
| [FluidAudio](https://github.com/AmpelAI/FluidAudio) | >= 0.12.1 | NVIDIA Parakeet local ASR (25 European languages, ~190ms) |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | >= 2.0.0 | Global hotkey recording & handling |
| [Yams](https://github.com/jpsim/Yams) | >= 5.0.0 | YAML parsing for snippets |
| [PhosphorSwift](https://github.com/phosphor-icons/swift) | >= 2.1.0 | Duotone icons for settings sidebar |

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

**Requirements:** macOS 14.0+, Apple Silicon (arm64 only), Xcode 15+

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
- **Multi-provider architecture:** `ASRProvider` protocol with `WhisperKitProvider` and `FluidAudioProvider` implementations. `ProviderCatalog` manages provider selection per language. `TranscriptionEngine` delegates to the active provider. `DictationSession` owns both providers and handles switching
- **Parakeet (FluidAudio):** NVIDIA Parakeet v3, ~470 MB on disk, ~190ms latency. Recommended for all 25 supported European languages (en, es, fr, de, it, pt, nl, pl, ro, ru, uk, sv, da, fi, el, hu, cs, sk, sl, hr, bg, et, lv, lt, mt). Single model covers all languages
- **WhisperKit models:** Each tier (tiny, small, medium) has both an English-only `.en` variant and a multilingual variant. Large v3 is multilingual only. English users see `.en` models + large; non-English users see multilingual models only. `SupportedLanguage.swift` lists 100+ Whisper-supported languages. Tiers: tiny (~77-153 MB, ~275ms), small (~217-218 MB, ~1.5s), medium (~1.5 GB, ~3s), large v3 turbo (~1 GB, ~3s)
- **Provider switching:** `DictationSession.switchProvider(to:)` unloads old provider, sets new one, loads model. Guards against loading FluidAudio when model isn't downloaded (prevents silent background downloads). Per-language overrides stored in `SettingsStore.providerOverrides`
- **Parakeet download progress:** `FluidAudioModelManager` polls cache directory size every 0.5s against known ~470 MB total. Caps at 99% during polling, sets 100% only on SDK confirmation. Note: SDK downloads to temp dir first then copies, so progress may jump
- **Parakeet model lifecycle:** `DictationSession` observes `FluidAudioModelManager.$isDownloaded` — auto-preloads when download completes, syncs `TranscriptionEngine` state when model is deleted (prevents stale `isModelLoaded`). Clears stale errors when download starts via `$isDownloading` subscriber
- **Model preloading:** The selected model loads at app launch (`AppDelegate.preloadModel()`) to avoid delay on first dictation. For FluidAudio, skips preload if model not downloaded
- **Model switching:** `DictationSession.switchModel(to:)` unloads current model and loads new one in background via `modelLoadTask`. Only one model in memory at a time. `TranscriptionEngine.loadedModelName` tracks which model is loaded to detect mismatches
- **Language switching:** `DictationSession.switchLanguage(to:)` prefers same-tier downloaded model for new language, falls back to smallest downloaded model, never selects undownloaded models
- **Model loading state:** `startDictation()` checks if model is ready synchronously — if not, sets `.loadingModel` state (shows spinner) and defers audio capture until load completes. `startTask` tracks the async work so it can be cancelled
- **Settings window:** Custom `NSWindow` with `NSHostingController` — not a SwiftUI `Settings` scene (which strips `.resizable`). Window has vertical resize only (width locked at 720), `setFrameAutosaveName` for persistence, `isReleasedWhenClosed = false` for reuse. Opened via `NSApp.sendAction(#selector(AppDelegate.openSettingsWindow))` from the popover to avoid `@MainActor` isolation issues with direct method calls
- **Settings sidebar:** Uses `HStack` with fixed-width `List`, not `NavigationSplitView` (which allows the user to collapse the sidebar by dragging the divider)
- **Race condition prevention:** State is set synchronously (`.loadingModel` or `.listening`) before the async Task in `startDictation()` to prevent re-entry. `startTask` and `stopTask` track async work; `cancelStop()` cancels both and resets `StreamingTranscriber` + `TranscriptionEngine` flight guards. `modelLoadTask` in `switchModel` is awaited by `startDictation` before proceeding
- **Transcription flight guards:** `TranscriptionEngine` uses `isFinalPending` (blocks new partials synchronously before any await) and `isPartialInFlight` (final waits for in-progress partial). Prevents concurrent provider calls while ensuring the final transcription is never dropped. `reset()` clears all guards to prevent stuck state after Task cancellation
- **Audio buffer draining:** `appendAudioBuffer()` uses fire-and-forget Tasks to bridge from audio callback thread to actor-isolated `AudioSampleBuffer`. `stopStreaming()` calls `flushAudioBuffer()` (actor serialization barrier) before final transcription to ensure all pending appends complete. Audio engine stops AFTER `stopStreaming()` returns, not before, to avoid losing trailing buffers
- **Live text subscription:** Created per-session in `startDictation()` and cancelled in `stopDictation()` to ensure it works across multiple sessions
- **Partial transcription:** Triggered every 1.5 seconds by timer in `StreamingTranscriber` for real-time preview
- **Silence detection:** Uses audio level threshold (0.05 normalized), starts timer when below, resets when above
- **Audio level calculation:** RMS normalization over sample frames with dB scaling (-50dB to 0dB → 0 to 1 range)
- **Permissions polling:** `PermissionManager` polls every 2 seconds for accessibility status changes (no system notification exists for this). Mic error auto-clears when permission is granted via Combine subscription in `DictationSession`
- **Text injection:** Uses `CGEvent` to synthesize keystrokes — requires Accessibility permission. 50ms delay before Cmd+V, 200ms wait after
- **Dock icon policy:** Dynamically toggles `NSApplication.setActivationPolicy()` based on `showDockIcon` setting and whether windows are open
- **Transcription logging:** Every session logged with duration, raw text, processed text, model used, and voice command metadata
- **LSUIElement focus:** Settings window and AppDelegate call `NSApp.activate(ignoringOtherApps: true)` since menu bar apps don't auto-activate
- **Floating indicator:** `NSPanel` with `.borderless` + `.nonactivatingPanel` — doesn't steal focus from the active app. Theme-aware: background, border, text, and waveform colors come from `IndicatorTheme`. Auto-resizes via `NSHostingView.fittingSize` after SwiftUI layout. Respects `showFloatingIndicator` setting. Uses `isHiding` flag to prevent race between show/hide animations
- **Indicator themes:** `IndicatorTheme` model with built-in themes (system, dark, light) and custom theme support via `CustomThemeStore`. Resolved via `SettingsStore.currentIndicatorTheme(isDarkMode:customThemes:)`
- **Non-speech filtering:** `TranscriptionEngine` strips `[...]`, `(...)`, and music symbols via regex before returning text. Catches all Whisper hallucination artifacts without needing a hardcoded list
- **Voice command toggles:** Disabled commands stored as comma-separated names in `SettingsStore.disabledVoiceCommands`. `VoiceCommandParser` skips disabled commands during processing
- **Voice command definitions:** Centralized in `VoiceCommandParser.allDefinitions` (static array), used by both the parser and the settings UI
- **Popover:** `StatusBarPopoverView` is split into private subviews: `PopoverHeaderView`, `PopoverBodyView`, `PopoverRecentView` (hover-to-copy with clipboard icon), `PopoverFooterView` (Settings + Quit with `FooterButtonStyle` hover/press effects). Uses `.preferredContentSize` sizing. Shows permission grant buttons when mic/accessibility not granted. Shows Parakeet download progress bar when downloading, "model required" hint when not downloaded, hides Start button when model isn't ready
- **Model name migration:** `SettingsStore.migrateModelNameIfNeeded()` runs at launch to fix orphaned model names from older versions
- **Accessibility reset:** `PermissionManager.requestAccessibility()` runs `tccutil reset` before prompting to clear stale entries from previous builds

## Stable Baseline

Commit `4b2d4ab` (v0.6.0) is the last known stable state with all features working: multi-provider (Parakeet + WhisperKit), download progress, popover model status, transcription race condition fixes. Previous stable: `3e8c852` (v0.5.0).

## Versioning & Releases

Uses semantic versioning (MAJOR.MINOR.PATCH):
- **PATCH** — bug fixes only
- **MINOR** — new features, backwards compatible
- **MAJOR** — breaking changes or "production-ready" milestone

### Release Process

To create a new release:

```bash
./scripts/release.sh 0.5.0
```

This script:
1. Validates semver format and checks clean main branch
2. Updates `MARKETING_VERSION` in `project.yml` (both targets)
3. Commits the version bump
4. Creates annotated git tag `v0.4.0`
5. Pushes commit + tag to origin

The tag push triggers `.github/workflows/release.yml` which:
1. Builds the app on Apple Silicon CI (`macos-14`)
2. Creates a DMG (`Dictava-0.4.0.dmg`)
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
| Toggle dictation | Option+Space | Editable via Settings > General |
| Copy last transcription | Option+Shift+Space | Fixed, copies to clipboard |

## Data Storage

| Data | Location | Format |
|------|----------|--------|
| Preferences | `~/Library/Preferences/com.dictava.app.plist` | UserDefaults |
| Snippets | `~/Library/Application Support/Dictava/snippets.yml` | YAML |
| Custom vocabulary | `~/Library/Application Support/Dictava/vocabulary.json` | JSON |
| Transcription history | `~/Library/Application Support/Dictava/transcription_logs.json` | JSON |
| Whisper models | `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/` | CoreML |
| Parakeet model | `AsrModels.defaultCacheDirectory(for: .v3)` (FluidAudio SDK managed) | CoreML (~470 MB) |

## Platform Constraints

- **Apple Silicon only** — `EXCLUDED_ARCHS[sdk=macosx*]: x86_64` in project.yml
- **Intel Mac support** would only require removing the arch exclusion (all APIs support x86_64, WhisperKit runs on CPU/GPU without Neural Engine)
- **Linux is not feasible** — requires full rewrite due to AppKit, AVFoundation, CGEvent, CoreML dependencies. Only the text processing pipeline and YAML stores are portable
