#!/usr/bin/env bash
# ==============================================================================
# VoiceTyper App & CLI (`voicetyper`) — Uninstaller Script
#
# Removes VoiceTyper.app bundle from Applications, voicetyper binary from PATH,
# and optionally purges ~/.voicetyper/ data.
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
RESET='\033[0m'

INSTALL_DIR="${PREFIX:-$HOME/.local/bin}"
VOICETYPER_HOME="${VOICETYPER_HOME:-$HOME/.voicetyper}"
BINARY_PATH="$INSTALL_DIR/voicetyper"
APP_DIR="${APP_DIR:-}"
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

echo -e "\n${BOLD}${CYAN}Uninstalling VoiceTyper...${RESET}\n"

# 1. Stop Running Instances
echo "🛑 Stopping running instances..."
pkill -i -x "VoiceTyper" 2>/dev/null || true
pkill -i -x "voicetyper" 2>/dev/null || true

# 2. Remove Application Bundles
echo "📦 Removing application bundles..."
for app_path in "/Applications/VoiceTyper.app" "$HOME/Applications/VoiceTyper.app" "${APP_DIR:+${APP_DIR}/VoiceTyper.app}"; do
    if [ -d "$app_path" ]; then
        if [ -w "$(dirname "$app_path")" ] || [ -w "$app_path" ]; then
            rm -rf "$app_path" 2>/dev/null || true
            echo -e "${GREEN}✔ Removed ${app_path}${RESET}"
        else
            echo "Removing application bundle from $app_path..."
            sudo rm -rf "$app_path" 2>/dev/null || true
            echo -e "${GREEN}✔ Removed ${app_path}${RESET}"
        fi
    fi
done

# 3. Remove Binary / Symlink
REMOVED=false
for bin_path in "$BINARY_PATH" "$HOME/.local/bin/voicetyper" "/usr/local/bin/voicetyper"; do
    if [ -f "$bin_path" ] || [ -L "$bin_path" ]; then
        if [ -w "$(dirname "$bin_path")" ] || [ -w "$bin_path" ]; then
            rm -f "$bin_path" 2>/dev/null || true
            echo -e "${GREEN}✔ Removed binary from ${bin_path}${RESET}"
            REMOVED=true
        else
            echo "Removing binary from $bin_path..."
            sudo rm -f "$bin_path" 2>/dev/null || true
            echo -e "${GREEN}✔ Removed binary from ${bin_path}${RESET}"
            REMOVED=true
        fi
    fi
done

if [ "$REMOVED" = false ]; then
    echo -e "${YELLOW}ℹ Binary not found.${RESET}"
fi

# 4. Optional Data Purge
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
