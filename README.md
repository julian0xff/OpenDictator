<p align="center">
  <img src=".github/icon.png" width="128" height="128" alt="OpenDictator icon">
</p>

<h1 align="center">OpenDictator</h1>

<p align="center">
  Local voice-to-text for macOS.<br>
  Press a hotkey, speak, and your words appear at the cursor — in any app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS_14+-blue?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-blue?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Apple_Silicon-black?logo=apple&logoColor=white" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

<p align="center">
  <a href="https://github.com/julian0xff/OpenDictator/releases/latest">Download</a> · <a href="#install">Install</a> · <a href="#features">Features</a>
</p>

---

Everything runs locally on your Mac using [NVIDIA Parakeet](https://github.com/AmpelAI/FluidAudio) and [WhisperKit](https://github.com/argmaxinc/WhisperKit). No internet needed after the initial model download. No data ever leaves your machine.

## Install

Download the latest `.dmg` from [Releases](https://github.com/julian0xff/OpenDictator/releases/latest), open it, and drag OpenDictator to Applications.

### Build from source

```bash
git clone https://github.com/julian0xff/OpenDictator.git
cd OpenDictator
xcodegen generate
xcodebuild -project OpenDictator.xcodeproj -scheme OpenDictator -destination 'platform=macOS,arch=arm64' build
```

> OpenDictator is ad-hoc signed (not notarized). macOS may show a security warning on first launch — right-click the app and choose **Open**, or go to **System Settings > Privacy & Security > Open Anyway**.

## Getting started

On first launch, a quick setup wizard asks for:

1. **Microphone** — so OpenDictator can hear you (audio stays on-device)
2. **Accessibility** — so it can type text at your cursor
3. **Model download** — pick Parakeet (recommended) or a WhisperKit model

Then just:

1. Press **Option+Space**
2. Talk
3. Press **Option+Space** again — or just stop talking
4. Your text appears wherever your cursor is

Works in any app — browsers, editors, Slack, email, Notes, anything.

## Features

- **100% local** — runs on Apple Silicon's Neural Engine. No cloud, no API keys, no subscriptions
- **Two speech engines** — NVIDIA Parakeet (~190ms, 25 languages) and WhisperKit (100+ languages)
- **Works everywhere** — text appears at the cursor in whatever app is focused
- **Live preview** — see partial transcription as you speak
- **Silence detection** — stops automatically when you go quiet
- **Voice commands** — say "new line", "select all", "delete that", "stop listening" and more
- **Spoken punctuation** — say "period", "comma", "question mark" and get the symbols
- **Filler word removal** — strips "um", "uh", "er" automatically
- **Text snippets** — trigger phrases that expand into longer text, with `{{date}}`, `{{time}}`, `{{clipboard}}` variables
- **Custom vocabulary** — fix words the model consistently gets wrong
- **Indicator themes** — customize the floating dictation indicator
- **Dictation history** — searchable log with stats and charts
- **Menu bar app** — lives in the system tray, zero clutter

## Models

### Parakeet (recommended)

| Model | Size | Speed | Languages |
|-------|------|-------|-----------|
| NVIDIA Parakeet v3 | ~470 MB | ~190ms | 25 European languages |

Supports: English, Spanish, French, German, Italian, Portuguese, Dutch, Polish, Romanian, Russian, Ukrainian, Swedish, Danish, Finnish, Greek, Hungarian, Czech, Slovak, Slovenian, Croatian, Bulgarian, Estonian, Latvian, Lithuanian, Maltese.

### WhisperKit

| Model | Size | Speed | Notes |
|-------|------|-------|-------|
| Tiny | ~39 MB | ~275ms | Fast, great for short dictation |
| Small | ~244 MB | ~1.5s | Good accuracy |
| Large v3 Turbo | ~809 MB | ~3s | Best quality, 100+ languages |

Models download once and are stored locally. The selected model preloads at launch for instant dictation.

## Voice commands

| Say | What happens |
|-----|-------------|
| "delete that" / "scratch that" | Undo |
| "select all" | Select All |
| "new line" | Line break |
| "new paragraph" | Double line break |
| "stop listening" | End dictation |

Each command can be toggled on/off in **Settings > Commands**.

## Spoken punctuation

| Say | Get |
|-----|-----|
| "period" / "full stop" | `.` |
| "comma" | `,` |
| "question mark" | `?` |
| "exclamation mark" | `!` |
| "colon" / "semicolon" | `:` / `;` |
| "dash" | `—` |
| "ellipsis" | `...` |
| "open/close quote" | `"` / `"` |
| "open/close paren" | `(` / `)` |

## Privacy

- No account, no login, no sign-up
- No telemetry, no analytics, no tracking
- No network calls after model download
- No cloud processing — everything runs on the Neural Engine
- Open source — read every line

## Keyboard shortcuts

| Action | Shortcut |
|--------|----------|
| Toggle dictation | **Option+Space** (customizable) |
| Copy last transcription | **Option+Shift+Space** |

## License

MIT
