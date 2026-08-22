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
APP_DIR="${APP_DIR:-}"

if [ -z "${APP_DIR}" ]; then
    if [ -w "/Applications" ]; then
        APP_DIR="/Applications"
    else
        APP_DIR="$HOME/Applications"
    fi
fi

mkdir -p "${PREFIX}"
mkdir -p "${VOICETYPER_HOME}"
mkdir -p "${APP_DIR}"

APP_BUNDLE="${APP_DIR}/VoiceTyper.app"

echo -e "Detected OS: ${BOLD}${OS}${RESET} | Arch: ${BOLD}${ARCH}${RESET}"
echo -e "App Bundle:  ${BOLD}${APP_BUNDLE}${RESET}"
echo -e "CLI Path:    ${BOLD}${PREFIX}/voicetyper${RESET}"
echo -e "Data Path:   ${BOLD}${VOICETYPER_HOME}${RESET}"
echo "───────────────────────────────────────────────────────────────────────────"

# 4. Build from Source or Clone
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

if [ -n "${REPO_ROOT}" ] && [ -f "${REPO_ROOT}/Package.swift" ] && grep -q '"VoiceTyper"' "${REPO_ROOT}/Package.swift"; then
    echo -e "✦ Building VoiceTyper from local source (${REPO_ROOT})..."
    if [ -f "${REPO_ROOT}/Resources/Info.plist" ]; then
        (cd "${REPO_ROOT}" && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "${REPO_ROOT}/Resources/Info.plist")
    else
        (cd "${REPO_ROOT}" && swift build -c release)
    fi
    BUILD_BIN="${REPO_ROOT}/.build/release/VoiceTyper"
    SOURCE_DIR="${REPO_ROOT}"
else
    echo -e "✦ Cloning and building VoiceTyper from https://github.com/burubur/voicetyper..."
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TMP_DIR}"' EXIT
    git clone https://github.com/burubur/voicetyper.git "${TMP_DIR}"
    if [ -f "${TMP_DIR}/Resources/Info.plist" ]; then
        (cd "${TMP_DIR}" && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "${TMP_DIR}/Resources/Info.plist")
    else
        (cd "${TMP_DIR}" && swift build -c release)
    fi
    BUILD_BIN="${TMP_DIR}/.build/release/VoiceTyper"
    SOURCE_DIR="${TMP_DIR}"
fi

# 5. Package macOS Application Bundle
echo -e "📦 Packaging macOS Application Bundle to ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
if [ -f "${SOURCE_DIR}/scripts/bundle_app.sh" ]; then
    bash "${SOURCE_DIR}/scripts/bundle_app.sh" --bin "${BUILD_BIN}" --output "${APP_BUNDLE}" --resources "${SOURCE_DIR}/Resources"
else
    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    mkdir -p "${APP_BUNDLE}/Contents/Resources"
    cp -f "${BUILD_BIN}" "${APP_BUNDLE}/Contents/MacOS/VoiceTyper"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/VoiceTyper"
    if [ -f "${SOURCE_DIR}/Resources/Info.plist" ]; then
        cp -f "${SOURCE_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
    fi
    echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"
    if [ -f "${SOURCE_DIR}/Resources/AppIcon.icns" ]; then
        cp -f "${SOURCE_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    fi
fi

# 6. Install CLI Symlink / Executable
echo -e "🔗 Linking CLI binary to ${PREFIX}/voicetyper..."
if [ -f "${PREFIX}/voicetyper" ] || [ -L "${PREFIX}/voicetyper" ]; then
    rm -f "${PREFIX}/voicetyper" 2>/dev/null || true
fi
# Remove stale /usr/local/bin/voicetyper if present to prevent PATH conflicts
if [ "${PREFIX}" != "/usr/local/bin" ] && [ -f "/usr/local/bin/voicetyper" ]; then
    echo -e "✦ Removing legacy /usr/local/bin/voicetyper to ensure ~/.local/bin takes precedence..."
    rm -f "/usr/local/bin/voicetyper" 2>/dev/null || sudo rm -f "/usr/local/bin/voicetyper" 2>/dev/null || true
fi

APP_INTERNAL_BIN="${APP_BUNDLE}/Contents/MacOS/VoiceTyper"
if [ -f "${APP_INTERNAL_BIN}" ]; then
    ln -sf "${APP_INTERNAL_BIN}" "${PREFIX}/voicetyper" 2>/dev/null || cp -f "${APP_INTERNAL_BIN}" "${PREFIX}/voicetyper"
else
    cp -f "${BUILD_BIN}" "${PREFIX}/voicetyper"
fi
chmod +x "${PREFIX}/voicetyper"

# 7. Ad-Hoc Codesigning
if command -v codesign >/dev/null 2>&1; then
    ENTITLEMENTS="${APP_BUNDLE}/Contents/Resources/VoiceTyper.entitlements"
    if [ -f "${ENTITLEMENTS}" ]; then
        codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}" 2>/dev/null || codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true
    else
        codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true
    fi
fi

# 8. Register with LaunchServices
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -f "${LSREGISTER}" ]; then
    "${LSREGISTER}" -f "${APP_BUNDLE}" 2>/dev/null || true
fi

echo "✓ Application bundle installed into ${APP_BUNDLE}"
echo "✓ CLI binary linked into ${PREFIX}/voicetyper"

# 9. Record source repo cache for omnipresent voicetyper upgrade
if [ -n "${REPO_ROOT}" ] && [ -f "${REPO_ROOT}/Package.swift" ]; then
    echo "${REPO_ROOT}" > "${VOICETYPER_HOME}/source_repo"
fi

# 10. Shell PATH Configuration
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

# 11. Restart Application
echo "🚀 Starting VoiceTyper in the background..."
pkill -i -x "VoiceTyper" 2>/dev/null || true
pkill -i -x "voicetyper" 2>/dev/null || true

if [ -f "${APP_INTERNAL_BIN}" ]; then
    nohup "${APP_INTERNAL_BIN}" > "${VOICETYPER_HOME}/app.log" 2>&1 &
else
    nohup "${PREFIX}/voicetyper" > "${VOICETYPER_HOME}/app.log" 2>&1 &
fi

echo "───────────────────────────────────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}✓ VoiceTyper successfully installed to ${APP_BUNDLE}${RESET}"
echo -e "  CLI accessible via: ${BOLD}${PREFIX}/voicetyper${RESET}"
echo "  Configuration and logs stored in ${VOICETYPER_HOME}/"
echo
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  • Spotlight Search: Search ${CYAN}VoiceTyper${RESET} in Spotlight / Launchpad to summon or launch."
echo -e "  • Menu Bar Agent:  Running in your menu bar (microphone icon)."
echo -e "  • Dictate Text:    Press and hold ${CYAN}Right Option${RESET} key to dictate anywhere."
echo -e "  • Voice Memo:      Press and hold ${CYAN}Shift + Right Option${RESET} to save voice memo."
echo -e "  • Check Status:    ${GREEN}voicetyper status${RESET}"
echo -e "  • Self-Upgrade:    ${GREEN}voicetyper upgrade${RESET}"
echo -e "  • Debug Logging:   ${GREEN}voicetyper --debug${RESET}"
echo
