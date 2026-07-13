.PHONY: download-models debug install uninstall clean

# Downloads all defined voice transcriber models sequentially via the bash script
download-models:
	./download-models.sh

# Recompiles and automatically re-runs VoiceTyper on any .swift file changes
debug:
	watchexec -e swift -r "swift build && .build/debug/VoiceTyper"

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
