#!/usr/bin/env bash
# ==============================================================================
# tests/verify_symbols.sh — Static Swift Symbol, Import & Exclusivity Quality Gate
# ==============================================================================
# Catches common Swift regressions even in environments without Apple SDKs:
# 1. Missing framework imports (Cocoa, Foundation, Accelerate)
# 2. Duplicate variable / property declarations within the same scope
# 3. Swift memory exclusivity violations (mutating array inside withUnsafeMutableBufferPointer)
# 4. Temporary pointer anti-patterns (&array inside DSPSplitComplex init)
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

echo "✦ RUNNING SWIFT STATIC SYMBOL & EXCLUSIVITY QUALITY GATE"
echo "───────────────────────────────────────────────────────────────────────────"

# 1. Check for Missing Imports in Sources/
echo "✦ Checking required framework imports..."
for swift_file in "${ROOT_DIR}"/Sources/VoiceTyper/*.swift; do
    filename="$(basename "${swift_file}")"
    
    # Files using NS* or AppKit classes must import Cocoa
    if grep -qE "NSApplication|NSWindow|NSView|NSEvent|NSStatusBar|NSMenu|NSAlert" "${swift_file}"; then
        if ! grep -qE "import (Cocoa|AppKit)" "${swift_file}"; then
            echo "❌ [${filename}] Uses AppKit/Cocoa symbols but missing 'import Cocoa'"
            FAILURES=$((FAILURES + 1))
        fi
    fi

    # Files using exit() or ProcessInfo must import Foundation or Cocoa/Darwin
    if grep -qE "\bexit\([0-9]+\)" "${swift_file}"; then
        if ! grep -qE "import (Foundation|Cocoa|Darwin)" "${swift_file}"; then
            echo "❌ [${filename}] Uses exit() but missing 'import Foundation' or 'import Cocoa'"
            FAILURES=$((FAILURES + 1))
        fi
    fi
done

# 2. Check for Duplicate Property Declarations in App.swift
echo "✦ Checking for duplicate class properties in App.swift..."
APP_SWIFT="${ROOT_DIR}/Sources/VoiceTyper/App.swift"
if [ -f "${APP_SWIFT}" ]; then
    DUPLICATES=$(grep -E '^\s*private (let|var) [a-zA-Z0-9]+' "${APP_SWIFT}" | awk '{print $3}' | sort | uniq -d || true)
    if [ -n "${DUPLICATES}" ]; then
        echo "❌ Duplicate property declarations detected in App.swift:"
        echo "${DUPLICATES}" | while read -r dup; do
            echo "   • ${dup}"
        done
        FAILURES=$((FAILURES + 1))
    fi
fi

# 3. Check for Swift Exclusivity Violations in withUnsafeMutableBufferPointer
echo "✦ Checking for Swift memory exclusivity violations in buffer closures..."
for swift_file in "${ROOT_DIR}"/Sources/VoiceTyper/*.swift; do
    filename="$(basename "${swift_file}")"
    
    # Check if a file creates a buffer pointer with 'withUnsafeMutableBufferPointer { <ptr> in'
    # and then directly accesses the enclosing array '<var>[' instead of '<ptr>['
    if grep -q "withUnsafeMutableBufferPointer" "${swift_file}"; then
        # Check if real[...] or imag[...] is modified inside AudioDSP.swift
        if [ "${filename}" = "AudioDSP.swift" ]; then
            if grep -nE "^\s*(real|imag)\[.*\]\s*[\*\+\-\/]?=" "${swift_file}"; then
                echo "❌ [AudioDSP.swift] Direct mutation of 'real[]' or 'imag[]' inside buffer closure causes exclusivity violation! Use 'realPtr[]' or 'imagPtr[]' instead."
                FAILURES=$((FAILURES + 1))
            fi
        fi
    fi
done

# 4. Check for Temporary Pointer Anti-Patterns
echo "✦ Checking for temporary pointer anti-patterns..."
if grep -nE "DSPSplitComplex\(realp:\s*&" "${ROOT_DIR}"/Sources/VoiceTyper/*.swift 2>/dev/null; then
    echo "❌ DSPSplitComplex init with inout '&' creates invalid temporary pointers! Use 'withUnsafeMutableBufferPointer' instead."
    FAILURES=$((FAILURES + 1))
fi

echo "───────────────────────────────────────────────────────────────────────────"
if [ "${FAILURES}" -eq 0 ]; then
    echo "✓ All Swift static symbol, import & exclusivity quality gates passed cleanly!"
    exit 0
else
    echo "❌ Quality gate failed with ${FAILURES} error(s)."
    exit 1
fi
