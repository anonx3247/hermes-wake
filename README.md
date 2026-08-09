# Hermes Wake

A local-first macOS voice client for a remote [Hermes Agent](https://github.com/NousResearch/hermes-agent) backend.

Hermes Wake listens locally for a configurable wake phrase, transcribes with Apple Neural Engine acceleration, connects to the same native WebSocket gateway used by Hermes Desktop, and speaks streamed agent responses with a configurable macOS voice.

## Interaction modes

### Turn mode (default)

1. Say **“Hey Cipher.”**
2. A start chime confirms that Hermes Wake is listening.
3. FluidAudio emits partial text while you speak.
4. Parakeet EOU detects the end of the utterance.
5. A completion chime plays and the text is submitted to Hermes.
6. Hermes’s streamed response is spoken sentence by sentence.
7. The client returns to wake-word-only mode.

### Conversation mode

Say **“run”**, **“conversation mode”**, or **“keep listening”** as a voice command. The microphone remains in conversational mode across turns, so the wake phrase is no longer required. Speaking while Hermes is talking stops speech playback and interrupts the current agent turn (barge-in).

Say **“turn mode”**, **“wake mode”**, or **“go to sleep”** to return to wake-word activation.

## Local voice commands

Commands are handled locally and are configurable in `~/.config/hermes-wake/config.json`.

| Defaults | Action |
| --- | --- |
| `new conversation`, `new convo` | Create and persist a fresh Hermes session |
| `stop`, `cancel` | Interrupt Hermes, stop speech, and return to turn mode |
| `pause`, `take five`, `hold on` | Pause until the wake phrase is spoken again |
| `resume`, `continue`, `I'm back` | Resume conversation mode |
| `run`, `conversation mode`, `keep listening` | Enter persistent conversation mode |
| `turn mode`, `wake mode` | Require the wake phrase again |
| `go to sleep`, `sleep`, `that's all` | Stop speaking and return to idle |

## Components

- **Wake word:** [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 3.3M open-vocabulary KWS model
- **Streaming STT:** [FluidAudio](https://github.com/FluidInference/FluidAudio) Parakeet EOU 120M, running locally through Core ML/ANE
- **Hermes transport:** authenticated `/api/ws` JSON-RPC—the same protocol as Hermes Desktop
- **Speech:** `AVSpeechSynthesizer`, with any installed macOS voice
- **Credentials:** password stored in macOS Keychain; never written to configuration

Porcupine and cloud speech services are not used.

## Requirements

- macOS 14+
- Swift 6 / current Xcode command-line tools
- Python 3 and [`uv`](https://docs.astral.sh/uv/) for compiling wake phrases
- A reachable `hermes serve` backend with username/password authentication

## Setup

```bash
git clone https://github.com/anonx3247/hermes-wake.git
cd hermes-wake
make setup
swift run hermes-wake models
swift run hermes-wake remote login --username YOUR_HERMES_USERNAME
make doctor
make run
```

`make setup` imports the remote URL from Hermes Desktop when available and downloads the checksum-pinned 15 MB wake-word model. `hermes-wake models` downloads FluidAudio’s Parakeet EOU Core ML model on first use.

The password prompt is hidden and stores the value under the Keychain service:

```text
ai.hermes.wake.remote
```

Do not place the password in JSON, environment variables, command arguments, or shell history.

## Configure wake phrases

Edit `~/.config/hermes-wake/config.json`:

```json
{
  "wakePhrases": [
    { "text": "HEY CIPHER", "score": 1.5, "threshold": 0.25 },
    { "text": "HEY SIPH", "score": 1.5, "threshold": 0.25 }
  ]
}
```

Then regenerate keyword tokens:

```bash
make keywords
```

No wake-word model retraining is required.

## Configure the spoken voice

List installed voices:

```bash
swift run hermes-wake voices
```

Copy an identifier into the configuration:

```json
{
  "speech": {
    "enabled": true,
    "voiceIdentifier": "com.apple.voice.compact.en-US.Samantha",
    "rate": 0.5,
    "volume": 1.0,
    "streamBySentence": true
  }
}
```

A null voice identifier uses the system default.

## Persistent sessions

Hermes Wake stores only the durable Hermes session ID at:

```text
~/.local/state/hermes-wake/session.json
```

On restart it calls `session.resume`. “New conversation” replaces that ID with a fresh `session.create`. Sessions and responses remain visible in Hermes Desktop.

## Security and approvals

The remote login uses the backend’s `/auth/password-login` cookie flow, mints a 30-second single-use WebSocket ticket, and connects to `/api/ws`. The password remains in Keychain.

Hermes approval, clarification, sudo, and secret requests are announced locally but must currently be resolved in Hermes Desktop. Voice confirmation for those sensitive requests is intentionally not automatic.

## Development

```bash
swift format lint --recursive --strict Sources Tests Package.swift
swift test
swift run hermes-wake doctor
```

## License

Apache-2.0. See [LICENSE](LICENSE).
