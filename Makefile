.PHONY: setup keywords build test run doctor

setup:
	./scripts/setup-wake-model.sh

keywords:
	~/.local/share/cipher-voice/tools-venv/bin/python ./scripts/compile-keywords.py

build:
	swift build

test:
	swift test

run:
	swift run cipher-voice listen

doctor:
	swift run cipher-voice doctor
