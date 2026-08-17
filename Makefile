.PHONY: help build compile test unit-test integration-test test-install verify check ci run dev stop download-models debug install uninstall clean \
        voicetyper.build voicetyper.compile voicetyper.test voicetyper.unit-test voicetyper.verify voicetyper.run voicetyper.dev \
        voicetyper.stop voicetyper.download-models voicetyper.debug voicetyper.install voicetyper.uninstall voicetyper.clean

help:
	@echo " __      __  _           _______                     "
	@echo " \\ \\    / / (_)         |__   __|                    "
	@echo "  \\ \\  / /__ _  ___ ___    | |_   _ _ __   ___ _ __ "
	@echo "   \\ \\/ / _ \\ |/ __/ _ \\   | | | | | '_ \\ / _ \\ '__|"
	@echo "    \\  / (_) | | (_|  __/   | | |_| | |_) |  __/ |   "
	@echo "     \\/ \\___/|_|\\___\\___|   |_|\\__, | .__/ \\___|_|   "
	@echo "                                __/ | |              "
	@echo "                               |___/|_|              "
	@echo "================================================================="
	@echo " VOICETYPER - Native macOS Offline Speech-to-Text Dictation"
	@echo "================================================================="
	@echo "Available commands:"
	@echo "  make build / compile     - Build the VoiceTyper Swift executable"
	@echo "  make test / unit-test    - Run Swift unit & installation lifecycle tests"
	@echo "  make verify / check / ci - Full quality gate (release build + all tests)"
	@echo "  make test-install        - Run isolated installation & CLI lifecycle test"
	@echo "  make run                 - Run VoiceTyper background menu bar agent"
	@echo "  make dev / debug         - Run VoiceTyper interactively in debug mode"
	@echo "  make stop                - Stop running VoiceTyper background processes"
	@echo "  make download-models     - Download Whisper & NVIDIA Parakeet models"
	@echo "  make install             - Build & install binary to ~/.local/bin"
	@echo "  make uninstall           - Uninstall binary and config from system"
	@echo "  make clean               - Remove build artifacts and local models"
	@echo ""
	@echo "Aliases (same as monorepo root):"
	@echo "  make voicetyper.build"
	@echo "  make voicetyper.run"
	@echo "  make voicetyper.test"
	@echo "  make voicetyper.verify"
	@echo "  make voicetyper.debug"
	@echo "  make voicetyper.download-models"
	@echo ""

# Builds the VoiceTyper executable target
build:
	swift build

compile:
	swift build -c release

# Runs Swift unit tests
unit-test:
	swift test

# Runs end-to-end installation & CLI lifecycle test suite
integration-test:
	./tests/test_install.sh

test-install: integration-test

# Runs both unit tests and installation lifecycle integration tests
test: unit-test integration-test

# Full quality gate verification (compile in release mode + all tests)
verify: compile test

check: verify

ci: verify

# Runs the VoiceTyper executable in the background
run:
	nohup voicetyper > /dev/null 2>&1 &

dev: debug

# Stops the background VoiceTyper application
stop:
	pkill -i -x "VoiceTyper" || true
	pkill -i -x "voicetyper" || true

# Downloads all defined voice transcriber models sequentially via the bash script
download-models:
	./download-models.sh

# Runs VoiceTyper interactively for debugging
debug:
	make stop
	swift run VoiceTyper --debug

# Installs VoiceTyper locally
install:
	./install.sh

# Uninstalls VoiceTyper locally
uninstall:
	./uninstall.sh

# Removes local build artifacts and downloaded whisper models
clean:
	rm -rf .build
	rm -rf "$$HOME/.voicetyper"

# VoiceTyper aliases
voicetyper.build: build
voicetyper.compile: compile
voicetyper.test: test
voicetyper.unit-test: unit-test
voicetyper.run: run
voicetyper.dev: dev
voicetyper.stop: stop
voicetyper.download-models: download-models
voicetyper.debug: debug
voicetyper.install: install
voicetyper.uninstall: uninstall
voicetyper.clean: clean
