.PHONY: build run stop download-models debug install uninstall clean

# Builds the VoiceTyper executable target
build:
	swift build

# Runs the VoiceTyper executable in the background
run:
	nohup voicetyper > /dev/null 2>&1 &

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
	swift run VoiceTyper

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
