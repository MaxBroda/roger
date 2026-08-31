# Roger

Push-to-talk dictation for macOS. Hold a key, speak, let go — the text lands in
whatever app has focus. Recognition runs entirely on device: no account, no
network, no API cost.

Roger is a normal Mac app with a Dock icon, a main window and settings on ⌘, —
and it can also run as a menu bar only tool that stays out of the way.

## Features

- **Push-to-talk** on a freely chosen key, system wide
- **Dictionary** for names and technical terms: primes recognition beforehand and
  corrects the text afterwards
- **History** with search, copy, and which correction applied
- **Level meter** while recording, in the window and as a floating HUD
- **Word count** across all dictations
- **Language picker** for the dictation language, independent of the UI language

## Requirements

| | |
|---|---|
| macOS | 26 or newer |
| Mac | Apple Silicon |
| Xcode Command Line Tools | `xcode-select --install` |

No Apple developer account needed to use Roger yourself.

## Install

```bash
git clone https://github.com/MaxBroda/roger.git
cd roger
./scripts/bundle.sh          # builds and installs ~/Applications/Roger.app
open ~/Applications/Roger.app
```

`swift build` alone is not enough — macOS ties microphone and accessibility
permissions to bundle identity and code signature, which a bare SwiftPM binary
does not have. You need the `.app`.

Moving the bundle to `/Applications` works, but permissions are also tied to the
path, so macOS asks for them again once.

## Permissions

The setup window on first launch asks for two:

| Permission | Needed for |
|---|---|
| **Microphone** | Recording |
| **Accessibility** | Intercepting the hotkey **and** inserting text into the target app |

Input Monitoring is **not** required, even though it sounds like it is — that one
covers passive event taps, while Roger's tap modifies events, which is
Accessibility's job.

After granting, **restart Roger** (the setup window offers a button). The event
tap is created at launch, so a running process never sees newly granted keyboard
events.

## Usage

**Hold Esc**, speak, release. The text appears at the cursor. On the first
dictation macOS downloads the speech model once; the menu bar shows progress.

The main window shows the level meter, the transcript log and the dictionary.
Settings are on ⌘, :

| Setting | What it does |
|---|---|
| **Push-to-talk** | Records the key to hold. Letters and digits are not allowed — modifier keys like right Option cost no latency |
| **Hold threshold** | How long the key must be held before recording starts (default 220 ms). Shorter presses are passed through to the system |
| **Language** | Dictation language, plus which speech models are installed |
| **Operation** | Menu bar only mode, see below |
| **Files** | Paths to dictionary and history, and clearing the history |

### Dictionary

Two kinds of entries: a **term** Roger should know (`Anthropic`), or a
**correction pair** — when Roger hears X, write Y (`cloud code` → `Claude Code`).
Terms are passed to the speech model as context; correction pairs run over the
finished text, whole words, case insensitive. The history shows which correction
applied to each dictation.

The file lives at `~/Library/Application Support/Roger/dictionary.json` and can
be edited by hand — changes show up without restarting. Roger ships with an example
dictionary from everyday development work (366 terms, 317 correction pairs); the
dictionary window has a "reset to example" button.

### Operating modes

Switchable under **Operation** in settings:

| | App (default) | Menu bar only |
|---|---|---|
| Dock icon | yes | no |
| ⌘Tab app switcher | yes | no |
| Window at launch | yes | no |
| Push-to-talk | yes | yes |

In menu bar only mode, windows and settings are reachable from the menu bar icon.
While a window is open Roger behaves like a regular app again, and returns to the
background when the last window closes. The switch takes effect once the last
window is closed.

## Project layout

```
Sources/
  RogerCore/                    platform-independent core, no UI
    Domain/                     DictationState, AudioChunk, Transcript, HotkeyBinding
    Ports/                      protocols: AudioCapturing, Transcribing, HotkeyMonitoring,
                                TextFormatting, TextInjecting, ContextBiasing
    Adapters/                   MicrophoneCapture, SpeechAnalyzerTranscriber, HoldKeyMonitor,
                                PasteboardInjector, DictionaryCorrector
    Dictionary/                 phrase model, rewrite rules, risk checks, JSON store
    History/                    dictation records and their store
    Support/                    file locations, directory watching
    DictationSession.swift      state machine: idle → recording → transcribing → injecting
    Permissions.swift           microphone, accessibility, speech authorization
    SpectrumAnalyzer.swift      FFT for the level meter
  Roger/                        the macOS app
    Design/                     design tokens and reusable components
    Main/                       main window: control head, transcript log, dictionary panel
    HUD/                        floating recording panel
    Settings/                   settings window, hotkey recorder
    Onboarding/                 first-run permission flow
    RogerApp.swift              application service owning the dictation stack
    AppDelegate.swift           wiring of session, hotkey and windows
  roger-doctor/                 diagnostics CLI
Tests/RogerCoreTests/           focused on the correction pass
Resources/                      icon, Info.plist, entitlements, bundled fonts
scripts/                        bundle.sh, release.sh, reset-permissions.sh
docs/                           design tokens, ideas
```

`DictationSession` talks to five ports; the adapters behind them are
interchangeable. Persistence is two JSON files in
`~/Library/Application Support/Roger/`: `dictionary.json` and `history.json`.

```bash
swift test
```

## Troubleshooting

```bash
swift run roger-doctor
```

Shows permissions, locale, and which speech models the system knows and has
installed. Note that the permission part applies to the diagnostics binary
itself, not to `Roger.app` — macOS decides per bundle.

```bash
./scripts/reset-permissions.sh
```

Drops Roger's entries from the permission database so macOS asks again. Needed
when the signature changes, e.g. when switching from ad-hoc to a certificate.

Permissions gone after a rebuild? Without a Developer ID certificate,
`bundle.sh` signs ad-hoc, and an ad-hoc signature changes with every build. The
setup window comes back up: two clicks, restart, done.

## Sharing a build

```bash
./scripts/release.sh 0.2.0    # → dist/Roger-0.2.0.zip plus SHA-256
```

Whether the ZIP opens on someone else's Mac depends on the signature. Ad-hoc
signed builds are reported as "damaged" by Gatekeeper after a download; the
recipient has to clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Roger.app
```

With a Developer ID and notarization the app opens without a prompt. Building
from source has no Gatekeeper hurdle at all.

## What's missing

- Further cleanup of the raw transcript: filler words, punctuation, lists
- A dictionary that fills itself instead of being maintained
- Voice commands (text snippets on request)
- Alternative ASR backends (Parakeet via MLX) — that's what `Transcribing` is for
- Notarization, updates

More detail in [`docs/ideen.md`](docs/ideen.md).

## License

MIT, see [LICENSE](LICENSE). The bundled fonts (Share Tech Mono, IBM Plex Mono)
are under the SIL Open Font License 1.1.
