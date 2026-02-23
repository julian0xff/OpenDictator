# Dictava

Local voice-to-text for macOS. Press a hotkey, speak, and your words appear at the cursor — in any app. Runs entirely on your Mac using [WhisperKit](https://github.com/argmaxinc/WhisperKit). No internet needed, no data leaves your machine.

## Install

### Homebrew (recommended)

```bash
brew install --cask julian0xff/tap/dictava
```

### Download

Grab the latest `.dmg` from [Releases](https://github.com/julian0xff/Dictava/releases), open it, and drag Dictava to Applications.

### Build from source

```bash
git clone https://github.com/julian0xff/Dictava.git
cd Dictava
xcodegen generate
xcodebuild -project Dictava.xcodeproj -scheme Dictava -destination 'platform=macOS,arch=arm64' build
```

The app lands in `~/Library/Developer/Xcode/DerivedData/Dictava-*/Build/Products/Debug/Dictava.app` — copy it to `/Applications`.

> Dictava is ad-hoc signed (not notarized). macOS may show a security warning on first launch. Right-click the app and choose **Open**, or go to **System Settings > Privacy & Security > Open Anyway**.

**Requires:** macOS 14.0+, Apple Silicon (M1/M2/M3/M4)

## Getting started

On first launch, the onboarding wizard walks you through three things:

1. **Microphone** — so Dictava can hear you (audio stays on-device)
2. **Accessibility** — so it can type text at your cursor and register the global hotkey
3. **Model download** — pick a WhisperKit model (Tiny is great to start with)

Then:

1. Press **Option+Space**
2. Talk
3. Press **Option+Space** again (or just stop talking — silence detection will kick in)
4. Your text appears wherever your cursor is

That's it. Works in any app — browsers, editors, Slack, email, Notes, anything.

## Features

- **100% local** — WhisperKit runs on Apple Silicon's Neural Engine. No cloud, no API keys, no subscriptions
- **Works everywhere** — text is injected at the cursor in whatever app is focused
- **Live preview** — see partial transcription as you speak
- **Silence detection** — stops automatically when you go quiet
- **Voice commands** — say "new line", "select all", "delete that", "stop listening" and more
- **Spoken punctuation** — say "period", "comma", "question mark" and get the symbols
- **Filler word removal** — strips "um", "uh", "er" automatically
- **Text snippets** — trigger phrases that expand into longer text, with `{{date}}`, `{{time}}`, `{{clipboard}}` variables
- **Custom vocabulary** — fix words Whisper consistently gets wrong
- **Multiple models** — from Tiny (~39 MB, fastest) to Large v3 Turbo (~809 MB, most accurate)
- **Indicator themes** — customize the floating dictation indicator's appearance
- **Dictation history** — searchable log with stats and charts
- **Menu bar app** — lives in the system tray, no dock icon clutter

## Voice commands

Say these at the end of your dictation:

| Say | What happens |
|-----|-------------|
| "delete that" / "scratch that" | Undo (Cmd+Z) |
| "select all" | Select All (Cmd+A) |
| "new line" | Line break |
| "new paragraph" | Double line break |
| "stop listening" | End dictation |

Each command can be toggled on/off in Settings > Commands.

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

## Settings

Click "Settings..." in the menu bar popover or press **Cmd+,**.

| Tab | What's there |
|-----|-------------|
| **General** | Hotkey, sounds, floating indicator, launch at login, permissions |
| **Appearance** | Indicator theme selection and customization |
| **Speech Recognition** | Model picker, download/delete models, silence timeout |
| **Text Processing** | Filler words, auto-capitalization, punctuation, vocabulary |
| **Snippets** | Create, edit, delete text expansions |
| **Commands** | Toggle individual voice commands |
| **History** | Stats dashboard, searchable transcription log |
| **Advanced** | Data folder, reset options |

## Models

| Model | Size | Speed | Notes |
|-------|------|-------|-------|
| Tiny (English) | ~39 MB | ~275ms | Fast, great for short dictation |
| Base (English) | ~74 MB | ~500ms | Good balance |
| Small (English) | ~244 MB | ~1.5s | Better accuracy |
| Large v3 Turbo | ~809 MB | ~3s | Best quality, multilingual |

Models download once from HuggingFace and are stored locally. The selected model preloads at launch for instant dictation.

## Privacy

Dictava is private by design:

- No account, no login, no sign-up
- No telemetry, no analytics, no tracking
- No network calls (zero `URLSession` usage in the codebase)
- No cloud processing — everything runs on the Neural Engine
- No third-party services
- Fully offline after the one-time model download
- Open source — read every line

## Keyboard shortcuts

| Action | Shortcut |
|--------|----------|
| Toggle dictation | Option+Space (customizable) |
| Copy last transcription | Option+Shift+Space |

## How it works under the hood

```
Option+Space → Mic capture → WhisperKit (on-device) → Text pipeline → Paste at cursor
```

The text pipeline runs your transcription through: voice command detection, punctuation conversion, snippet expansion, filler word removal, and vocabulary corrections — in that order.

Text injection works by briefly borrowing your clipboard: Dictava saves what's on it, places the transcription, simulates Cmd+V, then restores your original clipboard. All synthetic keystrokes are tagged with a marker (`0x44494354` — "DICT" in hex) to prevent feedback loops.

## License

MIT
