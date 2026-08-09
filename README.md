# Cipher Voice

A local-first, always-listening macOS wake-word service and bridge for [Hermes Agent](https://github.com/NousResearch/hermes-agent).

The first milestone is a working configurable wake-word listener. It uses [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) rather than a proprietary wake-word SDK.

## Why sherpa-onnx?

- Apache-2.0 licensed
- Runs entirely on the local Mac
- Native Apple Silicon support through Swift Package Manager
- Tiny 3.3M-parameter English keyword-spotting model
- **Open-vocabulary detection:** change phrases without training a classifier
- Per-phrase score and false-trigger threshold controls

The default phrases are **“Hey Cipher”** and **“Hey Siph.”**

## Current status

- [x] Configurable open-vocabulary wake phrases
- [x] Always-on macOS microphone capture
- [x] 16 kHz conversion and streaming keyword inference
- [x] Reproducible model download and keyword compiler
- [ ] FluidAudio streaming speech-to-text after activation
- [ ] End-of-utterance detection
- [ ] Hermes Responses API client over Tailscale
- [ ] Menu-bar app and login item

## Requirements

- Apple Silicon or Intel Mac running macOS 13+
- Xcode command-line tools / Swift 5.9+
- Python 3 (only for compiling human-readable phrases into model tokens)

No Picovoice account, API key, or cloud speech service is used.

## Setup

```bash
git clone https://github.com/anonx3247/cipher-voice.git
cd cipher-voice
make setup
make test
make run
```

`make setup` downloads a checksum-pinned 15 MB sherpa-onnx keyword model to:

```text
~/.local/share/cipher-voice/models/kws-gigaspeech-3.3M
```

The first `make run` asks macOS for microphone permission.

## Configure wake phrases

Edit `~/.config/cipher-voice/config.json`:

```json
{
  "wakePhrases": [
    { "text": "HEY CIPHER", "score": 1.5, "threshold": 0.25 },
    { "text": "HEY SIPH", "score": 1.5, "threshold": 0.25 }
  ]
}
```

Then regenerate the keyword tokens and restart the listener:

```bash
make keywords
make run
```

No model retraining is necessary. `score` makes a phrase more competitive during decoding; `threshold` controls how much acoustic confidence is required. Lower thresholds trigger more easily but can increase false positives.

## Commands

```bash
swift run cipher-voice init
swift run cipher-voice doctor
swift run cipher-voice listen
```

When a phrase is detected, the current milestone prints an event:

```text
[2026-08-08T18:42:10Z] Wake phrase detected: hey cipher
```

The next milestone will feed the already-open microphone stream into FluidAudio and submit the finalized utterance to a persistent Hermes conversation.

## Architecture

```text
AVAudioEngine microphone tap
          │
          ▼
AVAudioConverter (mono, 16 kHz Float32)
          │
          ▼
sherpa-onnx 3.3M open-vocabulary KWS
          │
          ├── idle: keep listening locally
          └── match: emit wake event → streaming STT (next milestone)
```

## License

Apache-2.0. See [LICENSE](LICENSE).
