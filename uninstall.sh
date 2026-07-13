#!/usr/bin/env bash

set -e

echo "🗑️ Uninstalling Swift VoiceTyper..."

INSTALL_DIR="/usr/local/bin"
BINARY_PATH="$INSTALL_DIR/voicetyper"

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

echo "ℹ️ Downloaded models are kept in $HOME/.voicetyper."
echo "   Run 'make clean' from the project root if you want to remove them."

echo ""
echo "✅ VoiceTyper has been successfully uninstalled."
