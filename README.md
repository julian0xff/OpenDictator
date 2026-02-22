# Dictava

Local voice dictation for macOS. Press a hotkey, speak, and text appears at your cursor — in any app. Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) running on Apple Silicon. No internet required, no data leaves your Mac.

## How It Works

```
Option+Space → Microphone → WhisperKit (on-device) → Text Pipeline → Paste at cursor
```

1. **You press Option+Space** — a floating pill indicator appears with a pulsing red dot
2. **Your voice is captured** — `AVAudioEngine` records microphone input at 16kHz mono. Audio is buffered in memory only, never saved to disk
3. **WhisperKit transcribes locally** — audio chunks are fed to a CoreML Whisper model running on the Neural Engine. Partial results appear in real-time every 1.5 seconds
4. **You stop** — either press Option+Space again, or silence detection triggers automatically after a configurable timeout
5. **Text is cleaned up** — the transcription passes through a pipeline that strips non-speech artifacts (`[Silence]`, `[clears throat]`), detects voice commands, converts spoken punctuation to symbols, removes filler words, expands snippets, and applies vocabulary corrections
6. **Text is injected at your cursor** — this is the clever part:
   - Dictava saves your current clipboard contents
   - Places the transcribed text on the clipboard
   - Simulates **Cmd+V** (paste) using a low-level `CGEvent` keystroke
   - Waits 200ms for the paste to complete
   - **Restores your original clipboard**

   This is why pressing Cmd+V after dictation pastes whatever you had copied *before* — Dictava doesn't leave your transcription on the clipboard. It borrows it for a split second and gives it back.

All synthetic keyboard events are tagged with a unique marker (`0x44494354` — "DICT" in hex) to avoid feedback loops.

## Features

- **Fully local & private** — WhisperKit CoreML models run entirely on-device. No cloud APIs, no network requests, no subscriptions
- **Works in any app** — Dictated text is injected at the cursor position via simulated keystrokes
- **Live preview** — See partial transcription in real-time as you speak
- **Silence detection** — Automatically stops recording after configurable silence timeout
- **Voice commands** — Say "new line", "select all", "delete that", "stop listening", and more. Each command can be individually enabled or disabled
- **Punctuation by voice** — Say "period", "comma", "question mark", etc. and get the actual symbols
- **Filler word removal** — Automatically strips "um", "uh", "er", and similar fillers
- **Text snippets** — Define trigger phrases that expand into longer text. Supports `{{date}}`, `{{time}}`, and `{{clipboard}}` variables. Full add, edit, and delete support
- **Custom vocabulary** — Fix words that Whisper consistently gets wrong
- **Non-speech filtering** — Automatically strips Whisper hallucinations like `[Silence]`, `[clears throat]`, `[BLANK_AUDIO]`, music symbols, and other non-speech annotations
- **Multiple Whisper models** — Choose from Tiny (~39 MB, fastest) to Large v3 Turbo (~809 MB, most accurate)
- **Menu bar app** — Lives in the system tray with no dock icon. Floating pill indicator shows recording state without stealing focus

## Privacy

Dictava is completely local and private by design:

- **No account required** — no sign-up, no login, no authentication of any kind
- **No telemetry** — zero analytics, zero tracking, zero usage reporting
- **No network calls** — the app makes no HTTP requests whatsoever (the codebase contains no `URLSession`, `URLRequest`, or any networking code)
- **No data collection** — your voice, transcriptions, snippets, and settings never leave your Mac
- **No cloud processing** — speech recognition runs entirely on-device via WhisperKit CoreML models on Apple Silicon
- **No third-party services** — no Firebase, no Sentry, no analytics SDKs, nothing
- **Fully offline** — works without an internet connection after the one-time model download
- **Open source** — the entire codebase is auditable

The only time Dictava touches the network is the initial WhisperKit model download from HuggingFace. After that, it never connects to the internet again.

## Requirements

- macOS 13.0+ (Ventura or later)
- Apple Silicon (M1/M2/M3/M4)
- Xcode 15+ (for building from source)

## Installation

### Download DMG

Download the latest `.dmg` from [Releases](https://github.com/julian0xff/Dictava/releases), open it, and drag Dictava to your Applications folder.

### Homebrew

```bash
brew install --cask julian0xff/tap/dictava
```

Update to the latest version:

```bash
brew upgrade --cask dictava
```

### Build from source

```bash
git clone https://github.com/julian0xff/Dictava.git
cd Dictava
xcodegen generate
xcodebuild -project Dictava.xcodeproj -scheme Dictava -destination 'platform=macOS,arch=arm64' build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/Dictava-*/Build/Products/Debug/Dictava.app`. Copy it to `/Applications` to install.

> **Note:** Dictava is ad-hoc signed (not notarized). On first launch, macOS may show a security warning. Right-click the app and select **Open**, or go to **System Settings > Privacy & Security** and click **Open Anyway**.

## Setup

On first launch, the onboarding wizard will guide you through:

1. **Microphone permission** — Required for audio capture. All audio stays on-device
2. **Accessibility permission** — Required for the global hotkey and typing text at your cursor
3. **Model download** — Download at least one WhisperKit model (Tiny recommended for speed)

## Usage

1. Press **Option+Space** (customizable in Settings → General)
2. Speak — you'll see a floating pill indicator with a pulsing red dot and audio waveform
3. Press **Option+Space** again to stop, or wait for silence detection
4. Your text appears at the cursor in whatever app is focused

### Voice Commands

Say these phrases at the end of your dictation to trigger actions:

| Say | Action |
|-----|--------|
| "delete that" / "scratch that" | Undo (Cmd+Z) |
| "undo that" / "undo" | Undo (Cmd+Z) |
| "select all" | Select All (Cmd+A) |
| "new line" | Insert line break |
| "new paragraph" | Insert double line break |
| "stop listening" / "stop dictation" | End dictation session |

Commands can be individually toggled on/off in Settings → Commands.

### Punctuation

| Say | Get |
|-----|-----|
| "period" / "full stop" | `.` |
| "comma" | `,` |
| "question mark" | `?` |
| "exclamation mark" | `!` |
| "colon" | `:` |
| "semicolon" | `;` |
| "dash" | `—` |
| "ellipsis" | `…` |
| "open quote" / "close quote" | `"` / `"` |
| "open paren" / "close paren" | `(` / `)` |

### Snippets

Create trigger phrases that expand into longer text. In Settings → Snippets:

- Click **+** to add a new snippet
- Click the **pencil icon** to edit an existing snippet
- Click the **trash icon** to delete a snippet

Template variables: `{{date}}` (current date), `{{time}}` (current time), `{{clipboard}}` (clipboard contents).

## Settings

Access settings by clicking the gear icon in the menu bar popover, or via the menu bar icon.

| Tab | What you can configure |
|-----|----------------------|
| **General** | Hotkey, start/stop sounds, floating indicator, launch at login, permissions |
| **Speech Recognition** | Whisper model selection/download/delete, silence timeout |
| **Text Processing** | Filler word removal, auto-capitalization, smart punctuation, custom vocabulary |
| **Snippets** | Add, edit, delete text expansion snippets |
| **Commands** | Enable/disable individual voice commands |
| **Advanced** | Data folder access, reset settings |

## Models

| Model | Size | Speed | Best for |
|-------|------|-------|----------|
| Tiny (English) | ~39 MB | ~275ms | Fast dictation, English only |
| Base (English) | ~74 MB | ~500ms | Good balance |
| Small (English) | ~244 MB | ~1.5s | Better accuracy |
| Large v3 Turbo | ~809 MB | ~3s | Best quality, multilingual |

Models are downloaded once and stored locally. The selected model is preloaded at app launch for instant dictation.

## Data Storage

| Data | Location |
|------|----------|
| Preferences | macOS UserDefaults |
| Snippets | `~/Library/Application Support/Dictava/snippets.yml` |
| Custom vocabulary | `~/Library/Application Support/Dictava/vocabulary.json` |
| Whisper models | `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/` |

## Development

A separate dev build target is available for testing changes without affecting the production install:

```bash
# Dev build (com.dictava.app.dev) — runs alongside production app
xcodebuild -project Dictava.xcodeproj -scheme DictavaDev -destination 'platform=macOS,arch=arm64' build
```

Both targets register the same hotkey, so only run one at a time.

## License

MIT
