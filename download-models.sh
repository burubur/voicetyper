#!/bin/bash
# Downloads whisper.cpp GGML models for VoiceTyper.
# Usage: ./download-model.sh [optional-specific-model]
# If no arguments are provided, all available models will be downloaded.

set -euo pipefail

MODEL_DIR="$HOME/.voicetyper"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

# Define all available models
MODELS=(
    "ggml-tiny.en.bin"
    "ggml-base.en.bin"
    "ggml-small.en.bin"
)

# Function to download a single model
download_model() {
    local RAW_NAME=$1
    # Strip .bin if the user accidentally included it to prevent .bin.bin
    local MODEL_NAME="${RAW_NAME%.bin}"
    local MODEL_FILE="$MODEL_DIR/${MODEL_NAME}.bin"

    if [ -f "$MODEL_FILE" ]; then
        echo "✅ Model already exists: ${MODEL_NAME}.bin"
        return
    fi

    echo "📥 Downloading ${MODEL_NAME}.bin..."
    mkdir -p "$MODEL_DIR"
    curl -L --progress-bar -o "$MODEL_FILE" "${BASE_URL}/${MODEL_NAME}.bin"
    echo "✅ Download complete: $MODEL_FILE"
    echo "----------------------------------------"
}

# Check if a specific model was requested
if [ -n "${1:-}" ]; then
    download_model "$1"
else
    echo "🚀 No specific model requested. Downloading ALL available models..."
    echo "----------------------------------------"
    for model in "${MODELS[@]}"; do
        download_model "$model"
    done
    echo "🎉 All downloads checked/completed."
fi
