#!/usr/bin/env bash
# ==============================================================================
# VoiceTyper App & CLI (`voicetyper`) — Uninstaller Script
#
# Removes voicetyper binary from PATH and optionally purges ~/.voicetyper/ data.
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
RESET='\033[0m'

INSTALL_DIR="${PREFIX:-/usr/local/bin}"
VOICETYPER_HOME="${VOICETYPER_HOME:-$HOME/.voicetyper}"
BINARY_PATH="$INSTALL_DIR/voicetyper"
PURGE=false
YES=false

for arg in "$@"; do
    case "$arg" in
        --purge|-p) PURGE=true ;;
        --yes|-y) YES=true ;;
        --help|-h)
            echo "Usage: ./uninstall.sh [--purge] [--yes]"
            echo "  --purge, -p    Remove ~/.voicetyper data and downloaded models directory"
            echo "  --yes, -y      Skip interactive confirmation prompt"
            exit 0
            ;;
    esac
done

echo -ne "${BOLD}${CYAN}"
echo " __      __  _           _______                     "
echo " \ \    / / (_)         |__   __|                    "
echo "  \ \  / /__ _  ___ ___    | |_   _ _ __   ___ _ __ "
echo "   \ \/ / _ \ |/ __/ _ \   | | | | | '_ \ / _ \ '__|"
echo "    \  / (_) | | (_|  __/   | | |_| | |_) |  __/ |   "
echo "     \/ \___/|_|\___\___|   |_|\__, | .__/ \___|_|   "
echo "                                __/ | |              "
echo "                               |___/|_|              "
echo -e "${RESET}"

if [ "$YES" != true ]; then
    read -r -p "⚠️  WARNING: Are you sure you want to uninstall VoiceTyper? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
fi

echo -e "\n${BOLD}${CYAN}Uninstalling VoiceTyper (${BINARY_PATH})...${RESET}\n"

# 1. Stop Running Instances
echo "🛑 Stopping running instances..."
pkill -i -x "VoiceTyper" 2>/dev/null || true
pkill -i -x "voicetyper" 2>/dev/null || true

# 2. Remove Binary
if [ -f "$BINARY_PATH" ]; then
    echo "Removing binary from $BINARY_PATH..."
    if [ ! -w "$INSTALL_DIR" ]; then
        sudo rm -f "$BINARY_PATH"
    else
        rm -f "$BINARY_PATH"
    fi
    echo -e "${GREEN}✔ Removed binary from ${BINARY_PATH}${RESET}"
else
    echo -e "${YELLOW}ℹ Binary ${BINARY_PATH} not found.${RESET}"
fi

# 3. Optional Data Purge
if [ -d "${VOICETYPER_HOME}" ]; then
    if [ "$PURGE" = true ]; then
        rm -rf "${VOICETYPER_HOME}"
        echo -e "${GREEN}✔ Purged VoiceTyper data and models at ${VOICETYPER_HOME}${RESET}"
    elif [ "$YES" = true ]; then
        echo -e "${YELLOW}ℹ Preserved models and settings at ${VOICETYPER_HOME} (use --purge to remove).${RESET}"
    else
        echo
        read -r -p "Do you want to delete models and voice history at ${VOICETYPER_HOME}? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "${VOICETYPER_HOME}"
            echo -e "${GREEN}✔ Purged VoiceTyper data at ${VOICETYPER_HOME}${RESET}"
        else
            echo -e "${YELLOW}ℹ Preserved models and data at ${VOICETYPER_HOME}${RESET}"
        fi
    fi
fi

echo
echo -e "${GREEN}${BOLD}✔ VoiceTyper has been successfully uninstalled.${RESET}"
