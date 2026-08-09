#!/usr/bin/env python3
"""Compile human-readable wake phrases into sherpa-onnx BPE keyword tokens."""

import json
import pathlib
import sys

try:
    import sentencepiece as spm
except ImportError:
    sys.exit("sentencepiece is required; run scripts/setup-wake-model.sh")


def expand(path: str) -> pathlib.Path:
    return pathlib.Path(path).expanduser().resolve()


def main() -> None:
    config_path = expand(sys.argv[1] if len(sys.argv) > 1 else "~/.config/cipher-voice/config.json")
    config = json.loads(config_path.read_text())
    model_dir = expand(config["modelDirectory"])
    output_path = expand(config["keywordsFile"])

    processor = spm.SentencePieceProcessor(model_file=str(model_dir / "bpe.model"))
    lines: list[str] = []
    for item in config["wakePhrases"]:
        phrase = item["text"].strip().upper()
        if not phrase:
            raise ValueError("wake phrases cannot be empty")
        identifier = "_".join("".join(c if c.isalnum() else " " for c in phrase).split()).lower()
        pieces = processor.encode(phrase, out_type=str)
        score = float(item.get("score", 1.5))
        threshold = float(item.get("threshold", 0.25))
        lines.append(f"{' '.join(pieces)} :{score:g} #{threshold:g} @{identifier}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n")
    print(f"Compiled {len(lines)} wake phrase(s) to {output_path}")
    for item in config["wakePhrases"]:
        print(f"  - {item['text']}")


if __name__ == "__main__":
    main()
