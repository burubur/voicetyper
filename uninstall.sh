#!/usr/bin/env bash

set -e

echo "🗑️ Uninstalling Swift VoiceTyper..."

INSTALL_DIR="/usr/local/bin"
BINARY_PATH="$INSTALL_DIR/voicetyper"
MODELS_DIR="$HOME/.voicetyper"

echo "🛑 Stopping running instances..."
pkill -i -f "voicetyper" || true

# 1. Remove the binary
if [ -f "$BINARY_PATH" ]; then
    echo "Removing binary from $BINARY_PATH..."
    if [ ! -w "$INSTALL_DIR" ]; then
        echo "Administrator privileges required to remove $BINARY_PATH"
        sudo rm "$BINARY_PATH"
    else
        rm "$BINARY_PATH"
    fi
    echo "✅ Binary removed."
else
    echo "⚠️ Binary not found at $BINARY_PATH. It might have already been uninstalled."
fi

# 2. Offer to remove downloaded models
if [ -d "$MODELS_DIR" ]; then
    echo ""
    read -p "Do you also want to delete the downloaded whisper models in $MODELS_DIR? (~466MB+ of space) (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$MODELS_DIR"
        echo "✅ Models removed."
    else
        echo "⚠️ Models kept intact."
    fi
fi

echo ""
echo "✅ VoiceTyper has been successfully uninstalled."
