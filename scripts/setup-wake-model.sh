#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$HOME/.config/cipher-voice"
CONFIG="$CONFIG_DIR/config.json"
DATA_DIR="$HOME/.local/share/cipher-voice"
MODEL_DIR="$DATA_DIR/models/kws-gigaspeech-3.3M"
TOOLS_VENV="$DATA_DIR/tools-venv"
ASSET="sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01-mobile.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/$ASSET"
SHA256="2e6ac2577310bfa2f4b6b5fab0478b868c9d0b2cb2c51b3e13b50581b588864d"

mkdir -p "$CONFIG_DIR" "$MODEL_DIR" "$DATA_DIR"
if [[ ! -f "$CONFIG" ]]; then
  cp "$ROOT/examples/config.example.json" "$CONFIG"
  echo "Created $CONFIG"
fi

if [[ ! -f "$MODEL_DIR/encoder.int8.onnx" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading the 15 MB open-vocabulary wake-word model..."
  curl --fail --location --progress-bar "$URL" --output "$tmp/$ASSET"
  actual="$(shasum -a 256 "$tmp/$ASSET" | awk '{print $1}')"
  [[ "$actual" == "$SHA256" ]] || { echo "Model checksum mismatch" >&2; exit 1; }
  tar -xjf "$tmp/$ASSET" -C "$tmp"
  source_dir="$tmp/${ASSET%.tar.bz2}"
  cp "$source_dir/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx" "$MODEL_DIR/encoder.int8.onnx"
  cp "$source_dir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx" "$MODEL_DIR/decoder.onnx"
  cp "$source_dir/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx" "$MODEL_DIR/joiner.int8.onnx"
  cp "$source_dir/tokens.txt" "$source_dir/bpe.model" "$MODEL_DIR/"
  echo "Installed model in $MODEL_DIR"
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required for the small keyword compiler environment." >&2
  echo "Install it with: brew install uv" >&2
  exit 1
fi
if [[ ! -x "$TOOLS_VENV/bin/python" ]] || ! "$TOOLS_VENV/bin/python" -c 'import sentencepiece' >/dev/null 2>&1; then
  rm -rf "$TOOLS_VENV"
  uv venv --python 3.13 "$TOOLS_VENV"
  uv pip install --python "$TOOLS_VENV/bin/python" 'sentencepiece==0.2.1'
fi
"$TOOLS_VENV/bin/python" "$ROOT/scripts/compile-keywords.py" "$CONFIG"

echo
echo "Wake-word setup complete. Run:"
echo "  swift run cipher-voice doctor"
echo "  swift run cipher-voice listen"
