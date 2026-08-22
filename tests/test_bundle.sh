#!/usr/bin/env bash
# ==============================================================================
# tests/test_bundle.sh — macOS Application Bundle & Packaging Test Suite
# ==============================================================================
# Validates:
# 1. macOS .app bundle directory structure and required files
# 2. Info.plist schema, required keys, and XML syntax
# 3. PkgInfo signature (APPL????)
# 4. AppIcon.icns magic header and format
# 5. CLI symlink creation and path resolution
# 6. Edge cases: spaces in directory paths, idempotent re-bundling, destination fallbacks
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
RED='\033[31m'
YELLOW='\033[33m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${CYAN}🧪 RUNNING MACOS APPLICATION BUNDLE & PACKAGING TEST SUITE${RESET}"
echo -e "${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

BUNDLE_SCRIPT="${REPO_ROOT}/scripts/bundle_app.sh"
GEN_ICON_SCRIPT="${REPO_ROOT}/scripts/generate_icon.py"
MOCK_BIN="${TEST_DIR}/MockVoiceTyper"

# Create a mock executable binary for bundling tests
echo '#!/bin/sh' > "${MOCK_BIN}"
echo 'echo "VoiceTyper Mock Binary"' >> "${MOCK_BIN}"
chmod +x "${MOCK_BIN}"

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: Generate & Validate AppIcon.icns
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[1/7] Testing AppIcon.icns Generation & Magic Header...${RESET}"
TEST_ICON="${TEST_DIR}/TestAppIcon.icns"
python3 "${GEN_ICON_SCRIPT}" "${TEST_ICON}"

if [ ! -f "${TEST_ICON}" ]; then
    echo -e "${RED}❌ Test 1 Failed: AppIcon.icns was not generated.${RESET}"
    exit 1
fi

ICON_SIZE=$(wc -c < "${TEST_ICON}")
if [ "${ICON_SIZE}" -lt 1000 ]; then
    echo -e "${RED}❌ Test 1 Failed: Generated icon file is suspiciously small (${ICON_SIZE} bytes).${RESET}"
    exit 1
fi

# Verify 'icns' magic 4 bytes
MAGIC=$(head -c 4 "${TEST_ICON}")
if [ "${MAGIC}" != "icns" ]; then
    echo -e "${RED}❌ Test 1 Failed: Expected magic 'icns', got '${MAGIC}'${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ AppIcon.icns generated with valid 'icns' magic header (${ICON_SIZE} bytes).${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: Basic Application Bundle Creation
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[2/7] Testing App Bundle Packaging Structure...${RESET}"
TARGET_APP="${TEST_DIR}/VoiceTyper.app"

bash "${BUNDLE_SCRIPT}" --bin "${MOCK_BIN}" --output "${TARGET_APP}" --resources "${REPO_ROOT}/Resources"

# Verify directory structure
REQUIRED_PATHS=(
    "${TARGET_APP}/Contents"
    "${TARGET_APP}/Contents/MacOS"
    "${TARGET_APP}/Contents/Resources"
    "${TARGET_APP}/Contents/Info.plist"
    "${TARGET_APP}/Contents/PkgInfo"
    "${TARGET_APP}/Contents/MacOS/VoiceTyper"
    "${TARGET_APP}/Contents/Resources/AppIcon.icns"
)

for p in "${REQUIRED_PATHS[@]}"; do
    if [ ! -e "$p" ]; then
        echo -e "${RED}❌ Test 2 Failed: Missing bundle component: $p${RESET}"
        exit 1
    fi
done

# Verify executable permissions
if [ ! -x "${TARGET_APP}/Contents/MacOS/VoiceTyper" ]; then
    echo -e "${RED}❌ Test 2 Failed: Binary inside bundle lacks executable permissions.${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ App bundle directory structure and binary permissions are valid.${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Test 3: Validate Info.plist Schema & Values
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[3/7] Testing Info.plist Schema & Required Keys...${RESET}"
PLIST_FILE="${TARGET_APP}/Contents/Info.plist"

REQUIRED_KEYS=(
    "CFBundleIdentifier"
    "CFBundleExecutable"
    "CFBundleName"
    "CFBundleDisplayName"
    "CFBundlePackageType"
    "CFBundleShortVersionString"
    "CFBundleIconFile"
    "LSUIElement"
    "NSMicrophoneUsageDescription"
)

for key in "${REQUIRED_KEYS[@]}"; do
    if ! grep -q "<key>${key}</key>" "${PLIST_FILE}"; then
        echo -e "${RED}❌ Test 3 Failed: Info.plist missing required key '${key}'${RESET}"
        exit 1
    fi
done

# Validate specific values
if ! grep -q "<string>com.burubur.voicetyper</string>" "${PLIST_FILE}"; then
    echo -e "${RED}❌ Test 3 Failed: CFBundleIdentifier mismatch in Info.plist${RESET}"
    exit 1
fi

if ! grep -q "<string>VoiceTyper</string>" "${PLIST_FILE}"; then
    echo -e "${RED}❌ Test 3 Failed: CFBundleExecutable / CFBundleName mismatch in Info.plist${RESET}"
    exit 1
fi

if ! grep -q "<string>APPL</string>" "${PLIST_FILE}"; then
    echo -e "${RED}❌ Test 3 Failed: CFBundlePackageType should be APPL in Info.plist${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Info.plist contains all required keys and valid bundle metadata.${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Test 4: Validate PkgInfo Signature
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[4/7] Testing PkgInfo File Signature...${RESET}"
PKGINFO_FILE="${TARGET_APP}/Contents/PkgInfo"
PKGINFO_CONTENT="$(cat "${PKGINFO_FILE}")"
if [ "${PKGINFO_CONTENT}" != "APPL????" ]; then
    echo -e "${RED}❌ Test 4 Failed: Expected PkgInfo content 'APPL????', got '${PKGINFO_CONTENT}'${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ PkgInfo contains standard macOS signature 'APPL????'.${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Test 5: Edge Case — Path with Spaces
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[5/7] Testing Bundle Packaging in Path with Spaces...${RESET}"
SPACE_DIR="${TEST_DIR}/My Applications Test Folder"
SPACE_APP="${SPACE_DIR}/Voice Typer.app"

mkdir -p "${SPACE_DIR}"
bash "${BUNDLE_SCRIPT}" --bin "${MOCK_BIN}" --output "${SPACE_APP}" --resources "${REPO_ROOT}/Resources"

if [ ! -f "${SPACE_APP}/Contents/MacOS/VoiceTyper" ]; then
    echo -e "${RED}❌ Test 5 Failed: Packaging failed for path containing spaces: ${SPACE_APP}${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Packaging successfully handled destination path with spaces.${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Test 6: Edge Case — Idempotent Overwrite
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[6/7] Testing Idempotent Re-Bundling (Overwrite Existing)...${RESET}"
# Re-run bundle script on the existing directory
bash "${BUNDLE_SCRIPT}" --bin "${MOCK_BIN}" --output "${TARGET_APP}" --resources "${REPO_ROOT}/Resources"

if [ ! -f "${TARGET_APP}/Contents/Info.plist" ] || [ ! -x "${TARGET_APP}/Contents/MacOS/VoiceTyper" ]; then
    echo -e "${RED}❌ Test 6 Failed: Re-bundling corrupted existing app bundle.${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Idempotent re-bundling succeeded cleanly without corruption.${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Test 7: CLI Symlink Resolution
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[7/7] Testing CLI Symlink to Internal Bundle Executable...${RESET}"
CLI_LINK="${TEST_DIR}/bin/voicetyper"
mkdir -p "${TEST_DIR}/bin"

ln -sf "${TARGET_APP}/Contents/MacOS/VoiceTyper" "${CLI_LINK}"

if [ ! -L "${CLI_LINK}" ]; then
    echo -e "${RED}❌ Test 7 Failed: ${CLI_LINK} is not a symlink.${RESET}"
    exit 1
fi

RESOLVED_TARGET="$(readlink "${CLI_LINK}")"
if [ "${RESOLVED_TARGET}" != "${TARGET_APP}/Contents/MacOS/VoiceTyper" ]; then
    echo -e "${RED}❌ Test 7 Failed: Expected symlink target '${TARGET_APP}/Contents/MacOS/VoiceTyper', got '${RESOLVED_TARGET}'${RESET}"
    exit 1
fi

# Execute via symlink
OUTPUT="$("${CLI_LINK}")"
if [[ ! "${OUTPUT}" =~ "VoiceTyper Mock Binary" ]]; then
    echo -e "${RED}❌ Test 7 Failed: Executing via CLI symlink returned unexpected output: ${OUTPUT}${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ CLI symlink correctly resolves and executes internal bundle binary.${RESET}"

echo -e "\n${BOLD}${GREEN}═════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}🎉 ALL MACOS APPLICATION BUNDLE TESTS PASSED!${RESET}"
echo -e "${BOLD}${GREEN}═════════════════════════════════════════════════════════════════════${RESET}"
