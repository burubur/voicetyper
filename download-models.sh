#!/bin/bash
# Downloads whisper.cpp GGML and NVIDIA Parakeet ONNX models for VoiceTyper.
# Usage: ./download-models.sh [optional-specific-model]
# If no arguments are provided, default models will be downloaded.

set -euo pipefail

MODEL_DIR="$HOME/.voicetyper"
WHISPER_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

# Define default models
MODELS=(
    "ggml-tiny.en.bin"
    "ggml-base.en.bin"
    "ggml-small.en.bin"
    "parakeet-tdt-1.1b"
)

# Function to download a single model
download_model() {
    local RAW_NAME=$1
    mkdir -p "$MODEL_DIR"

    if [[ "$RAW_NAME" == *"parakeet"* ]]; then
        local CLEAN_NAME="${RAW_NAME%.onnx}"
        CLEAN_NAME="${CLEAN_NAME%.tar.bz2}"
        if [[ "$CLEAN_NAME" != sherpa-onnx-* ]]; then
            CLEAN_NAME="sherpa-onnx-${CLEAN_NAME}"
        fi

        local TARGET_DIR="$MODEL_DIR/${CLEAN_NAME}"
        local TARGET_FILE="$MODEL_DIR/${CLEAN_NAME}.onnx"

        if [ -d "$TARGET_DIR" ] || [ -f "$TARGET_FILE" ]; then
            echo "✅ Parakeet model already exists: ${CLEAN_NAME}"
            return
        fi

        echo "📥 Downloading NVIDIA Parakeet model (${CLEAN_NAME})..."
        local TAR_FILE="$MODEL_DIR/${CLEAN_NAME}.tar.bz2"
        curl -L --progress-bar -o "$TAR_FILE" "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${CLEAN_NAME}.tar.bz2"
        tar -xjf "$TAR_FILE" -C "$MODEL_DIR"
        rm -f "$TAR_FILE"
        echo "✅ Parakeet download complete: $MODEL_DIR/${CLEAN_NAME}"
        echo "----------------------------------------"
        return
    fi

    # Standard Whisper GGML model
    local MODEL_NAME="${RAW_NAME%.bin}"
    local MODEL_FILE="$MODEL_DIR/${MODEL_NAME}.bin"

    if [ -f "$MODEL_FILE" ]; then
        echo "✅ Model already exists: ${MODEL_NAME}.bin"
        return
    fi

    echo "📥 Downloading ${MODEL_NAME}.bin..."
    curl -L --progress-bar -o "$MODEL_FILE" "${WHISPER_BASE_URL}/${MODEL_NAME}.bin"
    echo "✅ Download complete: $MODEL_FILE"
    echo "----------------------------------------"
}

# Check if a specific model was requested
if [ -n "${1:-}" ]; then
    download_model "$1"
else
    echo "🚀 Downloading default VoiceTyper models (Whisper + NVIDIA Parakeet)..."
    echo "----------------------------------------"
    for model in "${MODELS[@]}"; do
        download_model "$model"
    done
    echo "🎉 All downloads checked/completed."
fi
