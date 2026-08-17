#!/usr/bin/env bash
# ==============================================================================
# VoiceTyper App & CLI (`voicetyper`) — Installer Script for macOS
#
# Quick Install for Friends / Developers:
#   curl -sSf https://raw.githubusercontent.com/burubur/voicetyper/main/install.sh | sh
#
# Repository:
#   https://github.com/burubur/voicetyper
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
RESET='\033[0m'

echo -ne "${BOLD}${CYAN}"
echo " __      __  _           _______                     "
echo " \ \    / / (_)         |__   __|                    "
echo "  \ \  / /__ _  ___ ___    | |_   _ _ __   ___ _ __ "
echo "   \ \/ / _ \ |/ __/ _ \   | | | | | '_ \ / _ \ '__|"
echo "    \  / (_) | | (_|  __/   | | |_| | |_) |  __/ |   "
echo "     \/ \___/|_|\___\___|   |_|\__, | .__/ \___|_|   "
echo "                                __/ | |              "
echo "                               |___/|_|              "
echo -e "${RESET}${BOLD}Global Offline Voice Dictation & Transcription for macOS${RESET}"
echo -e "Repository: ${CYAN}https://github.com/burubur/voicetyper${RESET}\n"

echo "✦ VOICETYPER INSTALLATION"
echo "───────────────────────────────────────────────────────────────────────────"

# 1. Platform Detection
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

if [ "${OS}" != "darwin" ]; then
    echo -e "${YELLOW}! Warning: VoiceTyper is designed for macOS (Darwin). Detected OS: ${OS}.${RESET}"
fi

case "${ARCH}" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo -e "${YELLOW}! Warning: Architecture ${ARCH}. Will attempt standard install.${RESET}"
        ;;
esac

# 2. Check Requirements
if ! command -v swift >/dev/null 2>&1; then
    echo "❌ Swift compiler not found."
    echo "Please install Xcode Command Line Tools first by running: xcode-select --install"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "❌ Git is not installed."
    exit 1
fi

# 3. Determine Installation Path
PREFIX="${PREFIX:-$HOME/.local/bin}"
VOICETYPER_HOME="${VOICETYPER_HOME:-$HOME/.voicetyper}"

mkdir -p "${PREFIX}"
mkdir -p "${VOICETYPER_HOME}"

echo -e "Detected OS: ${BOLD}${OS}${RESET} | Arch: ${BOLD}${ARCH}${RESET}"
echo -e "Target Path: ${BOLD}${PREFIX}/voicetyper${RESET}"
echo -e "Data Path:   ${BOLD}${VOICETYPER_HOME}${RESET}"
echo "───────────────────────────────────────────────────────────────────────────"

# 4. Build from Source or Clone
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

if [ -n "${REPO_ROOT}" ] && [ -f "${REPO_ROOT}/Package.swift" ] && grep -q '"VoiceTyper"' "${REPO_ROOT}/Package.swift"; then
    echo -e "✦ Building VoiceTyper from local source (${REPO_ROOT})..."
    (cd "${REPO_ROOT}" && swift build -c release)
    BUILD_BIN="${REPO_ROOT}/.build/release/VoiceTyper"
else
    echo -e "✦ Cloning and building VoiceTyper from https://github.com/burubur/voicetyper..."
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TMP_DIR}"' EXIT
    git clone https://github.com/burubur/voicetyper.git "${TMP_DIR}"
    (cd "${TMP_DIR}" && swift build -c release)
    BUILD_BIN="${TMP_DIR}/.build/release/VoiceTyper"
fi

# 5. Install Binary
echo -e "📦 Installing binary to ${PREFIX}/voicetyper..."
if [ -f "${PREFIX}/voicetyper" ]; then
    rm -f "${PREFIX}/voicetyper" 2>/dev/null || true
fi
cp "${BUILD_BIN}" "${PREFIX}/voicetyper"
chmod +x "${PREFIX}/voicetyper"

if command -v codesign >/dev/null 2>&1; then
    if [ -f "${REPO_ROOT}/Resources/VoiceTyper.entitlements" ]; then
        codesign --force --deep --sign - --entitlements "${REPO_ROOT}/Resources/VoiceTyper.entitlements" "${PREFIX}/voicetyper" 2>/dev/null || codesign --force --sign - "${PREFIX}/voicetyper" 2>/dev/null || true
    else
        codesign --force --sign - "${PREFIX}/voicetyper" 2>/dev/null || true
    fi
fi

echo "✓ Binary installed into ${PREFIX}/voicetyper"

# 6. Record source repo cache for omnipresent voicetyper upgrade
if [ -n "${REPO_ROOT}" ] && [ -f "${REPO_ROOT}/Package.swift" ]; then
    echo "${REPO_ROOT}" > "${VOICETYPER_HOME}/source_repo"
fi

# 7. Shell PATH Configuration
SHELL_CONFIG=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
elif [ -f "$HOME/.profile" ]; then
    SHELL_CONFIG="$HOME/.profile"
fi

if [ -n "${SHELL_CONFIG}" ]; then
    if ! grep -q "${PREFIX}" "${SHELL_CONFIG}"; then
        echo "export PATH=\"${PREFIX}:\$PATH\"" >> "${SHELL_CONFIG}"
        echo -e "✓ Added ${PREFIX} to ${SHELL_CONFIG}"
    fi
fi

# 8. Restart Application
echo "🚀 Starting VoiceTyper in the background..."
pkill -i -x "VoiceTyper" 2>/dev/null || true
pkill -i -x "voicetyper" 2>/dev/null || true

nohup "${PREFIX}/voicetyper" > "${VOICETYPER_HOME}/app.log" 2>&1 &

echo "───────────────────────────────────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}✓ VoiceTyper successfully installed to ${PREFIX}/voicetyper${RESET}"
echo "  Configuration and logs stored in ${VOICETYPER_HOME}/"
echo
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  • Menu Bar Agent:  Running in your menu bar (microphone icon)."
echo -e "  • Dictate Text:    Press and hold ${CYAN}Right Option${RESET} key to dictate anywhere."
echo -e "  • Voice Memo:      Press and hold ${CYAN}Shift + Right Option${RESET} to save voice memo."
echo -e "  • Check Status:    ${GREEN}voicetyper status${RESET}"
echo -e "  • Self-Upgrade:    ${GREEN}voicetyper upgrade${RESET}"
echo -e "  • Debug Logging:   ${GREEN}voicetyper --debug${RESET}"
echo
