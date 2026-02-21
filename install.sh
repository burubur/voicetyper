#!/usr/bin/env bash

set -e

echo "🎙️ Installing Swift VoiceTyper..."

# 1. Check requirements
if ! command -v swift &> /dev/null; then
    echo "❌ Swift compiler not found."
    echo "Please install Xcode Command Line Tools first by running: xcode-select --install"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "❌ Git is not installed."
    exit 1
fi

# 2. Check if running locally or via remote script
if [ -f "Package.swift" ] && grep -q '"VoiceTyper"' Package.swift; then
    echo "📂 Running from local project source. Skipping clone."
else
    # Prepare temporary directory
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo "📂 Cloning repository..."
    # Adjust this URL if your repository is named differently or hosted elsewhere
    REPO_URL="https://github.com/burubur/voicetyper.git"
    git clone "$REPO_URL" "$TMP_DIR"
    cd "$TMP_DIR"
fi

# 3. Build the binary
echo "🏗️ Building VoiceTyper in release mode (this may take a few minutes)..."
swift build -c release

# 4. Download default model
echo "🧠 Downloading default whisper model (ggml-base.en.bin)..."
chmod +x download-models.sh
./download-models.sh ggml-base.en.bin

# 5. Install system-wide
INSTALL_DIR="/usr/local/bin"
echo "📦 Installing binary to $INSTALL_DIR/voicetyper..."

if [ ! -w "$INSTALL_DIR" ]; then
    echo "Administrator privileges required to copy to $INSTALL_DIR"
    sudo cp .build/release/VoiceTyper "$INSTALL_DIR/voicetyper"
else
    cp .build/release/VoiceTyper "$INSTALL_DIR/voicetyper"
fi

echo ""
echo "✅ VoiceTyper installed successfully!"

echo "🚀 Starting VoiceTyper in the background..."
pkill -i -f "voicetyper" || true
nohup voicetyper > /dev/null 2>&1 &

echo "It is now running in your menu bar (simple mic icon)."
echo "To see diagnostic logs, you can stop it and run it manually in a custom terminal: voicetyper --debug"
