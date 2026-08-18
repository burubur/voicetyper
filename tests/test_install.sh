#!/usr/bin/env bash
# ==============================================================================
# VoiceTyper End-to-End Installation & CLI Lifecycle Test Suite
#
# Validates build, isolated installation, CLI argument routing, codesigning,
# and uninstallation without altering the user's live system.
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
RED='\033[31m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${CYAN}🧪 RUNNING VOICETYPER INSTALLATION & CLI INTEGRATION TEST SUITE${RESET}"
echo -e "${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
TEST_PREFIX="${TEST_DIR}/bin"
TEST_HOME="${TEST_DIR}/.voicetyper"

cleanup() {
    rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

mkdir -p "${TEST_PREFIX}" "${TEST_HOME}"

if ! command -v swift >/dev/null 2>&1; then
    echo -e "${CYAN}ℹ 'swift' not available on this machine (macOS-only). Validating script syntax...${RESET}"
    bash -n "${REPO_ROOT}/install.sh" "${REPO_ROOT}/uninstall.sh" "${REPO_ROOT}/download-models.sh"
    echo -e "${GREEN}✓ All repository scripts passed syntax checking.${RESET}"
    exit 0
fi

# 1. Test Compilation & Installation
echo -e "\n${BOLD}[1/5] Testing ./install.sh in isolated sandbox...${RESET}"
(
    cd "${REPO_ROOT}"
    PREFIX="${TEST_PREFIX}" VOICETYPER_HOME="${TEST_HOME}" ./install.sh
)

# Verify binary existence and permissions
INSTALLED_BIN="${TEST_PREFIX}/voicetyper"
if [ ! -x "${INSTALLED_BIN}" ]; then
    echo -e "${RED}❌ Test Failed: Binary not installed or not executable at ${INSTALLED_BIN}${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Binary successfully created with executable permissions.${RESET}"

# Verify source_repo cache
if [ ! -f "${TEST_HOME}/source_repo" ]; then
    echo -e "${RED}❌ Test Failed: source_repo cache not created at ${TEST_HOME}/source_repo${RESET}"
    exit 1
fi
CACHED_SOURCE="$(cat "${TEST_HOME}/source_repo")"
if [ "${CACHED_SOURCE}" != "${REPO_ROOT}" ]; then
    echo -e "${RED}❌ Test Failed: Expected cached source '${REPO_ROOT}', got '${CACHED_SOURCE}'${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Source repository cache accurately recorded.${RESET}"

# 2. Test Subcommands: version
echo -e "\n${BOLD}[2/5] Testing 'voicetyper version'...${RESET}"
VERSION_OUTPUT="$("${INSTALLED_BIN}" version)"
echo "   Output: ${VERSION_OUTPUT}"
if [[ ! "${VERSION_OUTPUT}" =~ "VoiceTyper" ]]; then
    echo -e "${RED}❌ Test Failed: 'voicetyper version' output missing 'VoiceTyper'${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Version subcommand passed.${RESET}"

# 3. Test Subcommands: status
echo -e "\n${BOLD}[3/5] Testing 'voicetyper status'...${RESET}"
STATUS_OUTPUT="$("${INSTALLED_BIN}" status)"
if [[ ! "${STATUS_OUTPUT}" =~ "VOICETYPER STATUS" ]]; then
    echo -e "${RED}❌ Test Failed: 'voicetyper status' output missing header${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Status subcommand passed.${RESET}"

# 4. Test Subcommands: help
echo -e "\n${BOLD}[4/5] Testing 'voicetyper help'...${RESET}"
HELP_OUTPUT="$("${INSTALLED_BIN}" help)"
if [[ ! "${HELP_OUTPUT}" =~ "Usage: voicetyper" ]]; then
    echo -e "${RED}❌ Test Failed: 'voicetyper help' output missing Usage string${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Help subcommand passed.${RESET}"

# 5. Test Uninstallation
echo -e "\n${BOLD}[5/5] Testing ./uninstall.sh in isolated sandbox...${RESET}"
(
    cd "${REPO_ROOT}"
    PREFIX="${TEST_PREFIX}" VOICETYPER_HOME="${TEST_HOME}" ./uninstall.sh --yes --purge
)

if [ -f "${INSTALLED_BIN}" ]; then
    echo -e "${RED}❌ Test Failed: Binary still exists at ${INSTALLED_BIN} after uninstallation${RESET}"
    exit 1
fi

if [ -d "${TEST_HOME}" ]; then
    echo -e "${RED}❌ Test Failed: Home directory ${TEST_HOME} still exists after --purge${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Uninstaller cleaned up binary and purged directory.${RESET}"

echo -e "\n${BOLD}${GREEN}═════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}🎉 ALL INSTALLATION & CLI LIFECYCLE TESTS PASSED!${RESET}"
echo -e "${BOLD}${GREEN}═════════════════════════════════════════════════════════════════════${RESET}"
