#!/usr/bin/env bash
# ==============================================================================
# VoiceTyper macOS App Bundler (`scripts/bundle_app.sh`)
# Packages compiled Swift binary into a full-featured macOS application bundle:
# VoiceTyper.app/
# ├── Contents/
# │   ├── Info.plist
# │   ├── PkgInfo
# │   ├── MacOS/
# │   │   └── VoiceTyper
# │   └── Resources/
# │       ├── AppIcon.icns
# │       └── VoiceTyper.entitlements
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH=""
OUTPUT_APP=""
RESOURCES_DIR="${REPO_ROOT}/Resources"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin)
            BIN_PATH="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT_APP="$2"
            shift 2
            ;;
        --resources)
            RESOURCES_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./scripts/bundle_app.sh [--bin <path>] [--output <path.app>] [--resources <dir>]"
            exit 0
            ;;
        *)
            if [ -z "${OUTPUT_APP}" ]; then
                OUTPUT_APP="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "${OUTPUT_APP}" ]; then
    OUTPUT_APP="${REPO_ROOT}/build/VoiceTyper.app"
fi

if [ -z "${BIN_PATH}" ]; then
    # Look for release binary, then debug binary
    if [ -f "${REPO_ROOT}/.build/release/VoiceTyper" ]; then
        BIN_PATH="${REPO_ROOT}/.build/release/VoiceTyper"
    elif [ -f "${REPO_ROOT}/.build/arm64-apple-macosx/release/VoiceTyper" ]; then
        BIN_PATH="${REPO_ROOT}/.build/arm64-apple-macosx/release/VoiceTyper"
    elif [ -f "${REPO_ROOT}/.build/debug/VoiceTyper" ]; then
        BIN_PATH="${REPO_ROOT}/.build/debug/VoiceTyper"
    else
        # In case swift build hasn't run yet, try compiling if swift is available
        if command -v swift >/dev/null 2>&1; then
            echo -e "✦ Compiling VoiceTyper release binary..."
            (cd "${REPO_ROOT}" && swift build -c release)
            BIN_PATH="${REPO_ROOT}/.build/release/VoiceTyper"
        fi
    fi
fi

echo -e "✦ Packaging macOS Application Bundle..."
echo -e "  • Target App : ${BOLD}${OUTPUT_APP}${RESET}"
if [ -n "${BIN_PATH}" ]; then
    echo -e "  • Source Bin : ${BOLD}${BIN_PATH}${RESET}"
fi

# 1. Create App Bundle Directory Structure
mkdir -p "${OUTPUT_APP}/Contents/MacOS"
mkdir -p "${OUTPUT_APP}/Contents/Resources"

# 2. Copy Binary
if [ -n "${BIN_PATH}" ] && [ -f "${BIN_PATH}" ]; then
    cp -f "${BIN_PATH}" "${OUTPUT_APP}/Contents/MacOS/VoiceTyper"
    chmod +x "${OUTPUT_APP}/Contents/MacOS/VoiceTyper"
fi

# 3. Copy & Validate Info.plist
if [ -f "${RESOURCES_DIR}/Info.plist" ]; then
    cp -f "${RESOURCES_DIR}/Info.plist" "${OUTPUT_APP}/Contents/Info.plist"
else
    echo -e "${YELLOW}! Resources/Info.plist not found, creating default Info.plist...${RESET}"
    cat << 'EOF' > "${OUTPUT_APP}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.burubur.voicetyper</string>
    <key>CFBundleName</key>
    <string>VoiceTyper</string>
    <key>CFBundleDisplayName</key>
    <string>VoiceTyper</string>
    <key>CFBundleExecutable</key>
    <string>VoiceTyper</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.5.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceTyper requires microphone access for offline speech-to-text dictation.</string>
</dict>
</plist>
EOF
fi

# 4. Generate PkgInfo
echo -n "APPL????" > "${OUTPUT_APP}/Contents/PkgInfo"

# 5. Ensure AppIcon.icns
if [ -f "${RESOURCES_DIR}/AppIcon.icns" ]; then
    cp -f "${RESOURCES_DIR}/AppIcon.icns" "${OUTPUT_APP}/Contents/Resources/AppIcon.icns"
elif [ -f "${REPO_ROOT}/scripts/generate_icon.py" ]; then
    python3 "${REPO_ROOT}/scripts/generate_icon.py" "${OUTPUT_APP}/Contents/Resources/AppIcon.icns"
fi

# 6. Copy Entitlements
if [ -f "${RESOURCES_DIR}/VoiceTyper.entitlements" ]; then
    cp -f "${RESOURCES_DIR}/VoiceTyper.entitlements" "${OUTPUT_APP}/Contents/Resources/VoiceTyper.entitlements"
fi

# 7. Ad-Hoc Codesigning
if command -v codesign >/dev/null 2>&1; then
    ENTITLEMENTS="${OUTPUT_APP}/Contents/Resources/VoiceTyper.entitlements"
    if [ -f "${ENTITLEMENTS}" ]; then
        codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${OUTPUT_APP}" 2>/dev/null || codesign --force --deep --sign - "${OUTPUT_APP}" 2>/dev/null || true
    else
        codesign --force --deep --sign - "${OUTPUT_APP}" 2>/dev/null || true
    fi
fi

echo -e "${GREEN}✓ Successfully packaged ${OUTPUT_APP}${RESET}"
