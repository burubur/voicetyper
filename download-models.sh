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
    "parakeet-unified-0.6b"
)

# Function to download a single model
download_model() {
    local RAW_NAME=$1
    mkdir -p "$MODEL_DIR"

    if [[ "$RAW_NAME" == *"parakeet"* ]]; then
        local ASSET_NAME=""
        case "$RAW_NAME" in
            *"110m"*)
                ASSET_NAME="sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"
                ;;
            *)
                ASSET_NAME="sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming"
                ;;
        esac

        local TARGET_DIR="$MODEL_DIR/${ASSET_NAME}"

        if [ -d "$TARGET_DIR" ]; then
            echo "✅ Parakeet model already exists: ${ASSET_NAME}"
            return
        fi

        echo "📥 Downloading NVIDIA Parakeet model (${ASSET_NAME})..."
        local TAR_FILE="$MODEL_DIR/${ASSET_NAME}.tar.bz2"

        # Remove any lingering invalid archive file from previous failed attempts
        rm -f "$TAR_FILE"

        if curl -fL --progress-bar -o "$TAR_FILE" "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${ASSET_NAME}.tar.bz2"; then
            tar -xjf "$TAR_FILE" -C "$MODEL_DIR"
            rm -f "$TAR_FILE"
            echo "✅ Parakeet download complete: $TARGET_DIR"
            echo "----------------------------------------"
        else
            rm -f "$TAR_FILE"
            echo "❌ Failed to download Parakeet model: ${ASSET_NAME}"
            return 1
        fi
        return
    fi

    # Standard Whisper GGML model
    local MODEL_NAME="${RAW_NAME%.bin}"
    local MODEL_FILE="$MODEL_DIR/${MODEL_NAME}.bin"

    if [ -f "$MODEL_FILE" ] && [ -s "$MODEL_FILE" ]; then
        echo "✅ Model already exists: ${MODEL_NAME}.bin"
        return
    fi

    echo "📥 Downloading ${MODEL_NAME}.bin..."
    if curl -fL --progress-bar -o "$MODEL_FILE" "${WHISPER_BASE_URL}/${MODEL_NAME}.bin"; then
        echo "✅ Download complete: $MODEL_FILE"
        echo "----------------------------------------"
    else
        rm -f "$MODEL_FILE"
        echo "❌ Failed to download Whisper model: ${MODEL_NAME}.bin"
        return 1
    fi
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
