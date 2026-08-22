.PHONY: help build compile app bundle icon test unit-test test-bundle integration-test test-install verify check ci run dev stop download-models debug install uninstall clean \
        voicetyper.build voicetyper.compile voicetyper.app voicetyper.bundle voicetyper.test voicetyper.unit-test voicetyper.test-bundle voicetyper.verify voicetyper.run voicetyper.dev \
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
	@echo "  make app / bundle        - Package full macOS Application (VoiceTyper.app)"
	@echo "  make icon                - Generate high-res Apple AppIcon.icns"
	@echo "  make test / unit-test    - Run Swift unit, bundle & lifecycle tests"
	@echo "  make verify / check / ci - Full quality gate (release build + all tests)"
	@echo "  make test-install        - Run isolated installation & CLI lifecycle test"
	@echo "  make test-bundle         - Run macOS Application bundle test suite"
	@echo "  make run                 - Run VoiceTyper background menu bar agent"
	@echo "  make dev / debug         - Run VoiceTyper interactively in debug mode"
	@echo "  make stop                - Stop running VoiceTyper background processes"
	@echo "  make download-models     - Download Whisper & NVIDIA Parakeet models"
	@echo "  make install             - Build & install VoiceTyper.app and CLI symlink"
	@echo "  make uninstall           - Uninstall binary and app bundle from system"
	@echo "  make clean               - Remove build artifacts and local models"
	@echo ""
	@echo "Aliases (same as monorepo root):"
	@echo "  make voicetyper.build"
	@echo "  make voicetyper.app"
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
	@if [ -f "Resources/Info.plist" ]; then \
		swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$$(pwd)/Resources/Info.plist"; \
	else \
		swift build -c release; \
	fi

# Packages the standalone macOS application bundle
app: compile
	./scripts/bundle_app.sh

bundle: app

# Generates macOS AppIcon.icns
icon:
	./scripts/generate_icon.py Resources/AppIcon.icns

# Runs Swift unit tests & static symbol quality gates
unit-test:
	./tests/verify_symbols.sh
	@if command -v swift >/dev/null 2>&1; then \
		swift test; \
	else \
		echo "ℹ️  'swift' toolchain not detected in current Linux environment."; \
		echo "   VoiceTyper requires macOS (AppKit/AVFoundation/Accelerate)."; \
		echo "✦ Performing local script syntax & lint quality gates..."; \
		bash -n install.sh uninstall.sh download-models.sh scripts/bundle_app.sh tests/test_install.sh tests/test_bundle.sh tests/verify_symbols.sh && \
		echo "✓ All repository scripts passed local syntax validation."; \
		echo "✦ Run 'make test' on your macOS machine or check GitHub Actions CI:"; \
		echo "   https://github.com/burubur/voicetyper/actions"; \
	fi

# Runs macOS application bundle verification suite
test-bundle:
	./tests/test_bundle.sh

# Runs end-to-end installation & CLI lifecycle test suite
integration-test:
	./tests/test_install.sh

test-install: integration-test

# Runs both unit tests, bundle packaging tests, and installation lifecycle integration tests
test: unit-test test-bundle integration-test

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
	rm -rf .build build
	rm -rf "$$HOME/.voicetyper"

# VoiceTyper aliases
voicetyper.build: build
voicetyper.compile: compile
voicetyper.app: app
voicetyper.bundle: bundle
voicetyper.test: test
voicetyper.unit-test: unit-test
voicetyper.test-bundle: test-bundle
voicetyper.run: run
voicetyper.dev: dev
voicetyper.stop: stop
voicetyper.download-models: download-models
voicetyper.debug: debug
voicetyper.install: install
voicetyper.uninstall: uninstall
voicetyper.clean: clean
