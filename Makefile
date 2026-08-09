.PHONY: setup keywords build test run doctor voices

setup:
	./scripts/setup-wake-model.sh

keywords:
	~/.local/share/hermes-wake/tools-venv/bin/python ./scripts/compile-keywords.py

build:
	swift build

test:
	swift test

run:
	swift run hermes-wake listen

doctor:
	swift run hermes-wake doctor

voices:
	swift run hermes-wake voices
