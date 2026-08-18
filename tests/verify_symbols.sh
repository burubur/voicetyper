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

# 2. Check for Duplicate Property & Function Declarations (Scope-Aware)
echo "✦ Checking for duplicate class properties and functions across Swift sources..."
python3 - "${ROOT_DIR}" << 'EOF' || FAILURES=$((FAILURES + 1))
import os, re, sys

root_dir = sys.argv[1]
sources_dir = os.path.join(root_dir, "Sources", "VoiceTyper")

failures = 0
for fname in sorted(os.listdir(sources_dir)):
    if not fname.endswith(".swift"):
        continue
    fpath = os.path.join(sources_dir, fname)
    with open(fpath, "r", encoding="utf-8") as f:
        lines = f.readlines()
    
    current_scope = None
    brace_depth = 0
    scope_start_depth = 0
    scope_props = {}
    scope_funcs = {}
    in_function_depth = 0
    
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
            
        # Match class/struct/actor/extension/enum definition
        m_scope = re.match(r'^\s*(final\s+)?(public\s+|private\s+|internal\s+)?(class|struct|actor|extension|enum)\s+([A-Za-z0-9_]+)', line)
        if m_scope:
            current_scope = m_scope.group(4)
            scope_start_depth = brace_depth
            if current_scope not in scope_props:
                scope_props[current_scope] = set()
                scope_funcs[current_scope] = set()
        
        # Track opening/closing braces
        open_braces = line.count("{")
        close_braces = line.count("}")
        
        if current_scope:
            # Check function declaration
            m_func = re.match(r'^\s*(@objc\s+)?(private\s+|public\s+|internal\s+)?func\s+([A-Za-z0-9_]+)\s*(\([^\)]*\))', line)
            if m_func:
                func_name = m_func.group(3)
                param_sig = m_func.group(4)
                # Normalize params to distinguish overloads vs exact duplicates
                sig = f"{func_name}{param_sig}"
                if sig in scope_funcs[current_scope]:
                    print(f"❌ [{fname}:{i}] Duplicate function redeclaration 'func {sig}' in '{current_scope}'")
                    failures += 1
                else:
                    scope_funcs[current_scope].add(sig)

            # Check class-level property declaration (only when directly in class scope, not inside a function)
            if brace_depth == scope_start_depth + 1 and not m_func:
                m_prop = re.match(r'^\s*(private\s+|public\s+|internal\s+)?(static\s+)?(let|var)\s+([A-Za-z0-9_]+)\s*[:=]', line)
                if m_prop:
                    prop_name = m_prop.group(4)
                    if prop_name in scope_props[current_scope]:
                        print(f"❌ [{fname}:{i}] Duplicate property declaration '{prop_name}' in '{current_scope}'")
                        failures += 1
                    else:
                        scope_props[current_scope].add(prop_name)
                        
        brace_depth += (open_braces - close_braces)
        if current_scope and brace_depth <= scope_start_depth:
            current_scope = None

if failures > 0:
    sys.exit(1)
EOF

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

# 5. Check for NSUserInterfaceItemIdentifier missing rawValue label
echo "✦ Checking for NSUserInterfaceItemIdentifier rawValue label requirement..."
if grep -nE "NSUserInterfaceItemIdentifier\([^r]" "${ROOT_DIR}"/Sources/VoiceTyper/*.swift 2>/dev/null; then
    echo "❌ NSUserInterfaceItemIdentifier requires 'rawValue:' label parameter (e.g. NSUserInterfaceItemIdentifier(rawValue: ...))."
    FAILURES=$((FAILURES + 1))
fi

# 6. Cross-File Type & Member Resolution Gate
echo "✦ Checking cross-file symbol and member references across all Swift sources..."
python3 - "${ROOT_DIR}" << 'EOF' || FAILURES=$((FAILURES + 1))
import os, re, sys

root_dir = sys.argv[1]
sources_dir = os.path.join(root_dir, "Sources", "VoiceTyper")

# Pass 1: Build symbol index of all internal types, their members, and access levels
type_members = {}  # { "TypeName": { "methodName", "propertyName", "shared", ... } }
type_private_members = {} # { "TypeName": { "privateMethod", "privateProp" } }
type_declarations = {} # { "TypeName": "File.swift" }

for fname in sorted(os.listdir(sources_dir)):
    if not fname.endswith(".swift"):
        continue
    fpath = os.path.join(sources_dir, fname)
    with open(fpath, "r", encoding="utf-8") as f:
        lines = f.readlines()
    
    type_stack = []  # [(TypeName, start_brace_depth)]
    brace_depth = 0
    
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
            
        # Match class/struct/actor/enum/protocol/extension definition
        m_type = re.match(r'^\s*(final\s+)?(public\s+|private\s+|internal\s+)?(class|struct|actor|enum|protocol|extension)\s+([A-Za-z0-9_]+)', line)
        if m_type:
            type_name = m_type.group(4)
            if type_name not in type_members:
                type_members[type_name] = set()
                type_private_members[type_name] = set()
                type_declarations[type_name] = fname
            type_stack.append((type_name, brace_depth))
        
        open_braces = line.count("{")
        close_braces = line.count("}")
        
        if type_stack:
            curr_type = type_stack[-1][0]
            # Match function
            m_func = re.match(r'^\s*(@objc\s+)?(public\s+|private\s+|internal\s+|fileprivate\s+)?(static\s+|class\s+)?func\s+([A-Za-z0-9_]+)', line)
            if m_func:
                name = m_func.group(4)
                type_members[curr_type].add(name)
                vis = m_func.group(2) or ""
                if "private" in vis or "fileprivate" in vis:
                    type_private_members[curr_type].add(name)
                
            # Match property
            m_prop = re.match(r'^\s*(public\s+|private\s+|internal\s+|fileprivate\s+)?(static\s+|class\s+)?(let|var)\s+([A-Za-z0-9_]+)', line)
            if m_prop:
                name = m_prop.group(4)
                type_members[curr_type].add(name)
                vis = m_prop.group(1) or ""
                if "private" in vis or "fileprivate" in vis:
                    type_private_members[curr_type].add(name)
                
            # Match enum case
            m_case = re.match(r'^\s*case\s+([A-Za-z0-9_]+)', line)
            if m_case:
                type_members[curr_type].add(m_case.group(1))
                
        brace_depth += (open_braces - close_braces)
        while type_stack and brace_depth <= type_stack[-1][1]:
            type_stack.pop()

# Pass 2: Verify member calls on known internal types and access levels
failures = 0
for fname in sorted(os.listdir(sources_dir)):
    if not fname.endswith(".swift"):
        continue
    fpath = os.path.join(sources_dir, fname)
    with open(fpath, "r", encoding="utf-8") as f:
        lines = f.readlines()
        
    type_stack = []
    brace_depth = 0
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
            
        m_type = re.match(r'^\s*(final\s+)?(public\s+|private\s+|internal\s+)?(class|struct|actor|enum|protocol|extension)\s+([A-Za-z0-9_]+)', line)
        if m_type:
            type_stack.append((m_type.group(4), brace_depth))
            
        open_braces = line.count("{")
        close_braces = line.count("}")
        curr_enclosing = type_stack[-1][0] if type_stack else None
            
        # Match <TypeName>.(shared\.)?<member>
        for type_name, members in type_members.items():
            pattern = rf'\b{type_name}\s*\.\s*(shared\s*\.\s*)?([a-zA-Z0-9_]+)'
            for m in re.finditer(pattern, line):
                member = m.group(2)
                if member in ("self", "init", "rawValue", "allCases", "Type", "shared", "sharedInstance"):
                    continue
                if member not in members:
                    print(f"❌ [{fname}:{i}] Type '{type_name}' (defined in {type_declarations[type_name]}) has no member '{member}'!")
                    failures += 1
                elif member in type_private_members.get(type_name, set()) and curr_enclosing != type_name:
                    print(f"❌ [{fname}:{i}] Member '{member}' of type '{type_name}' is private and cannot be called from '{curr_enclosing or fname}'!")
                    failures += 1
                    
        brace_depth += (open_braces - close_braces)
        while type_stack and brace_depth <= type_stack[-1][1]:
            type_stack.pop()

if failures > 0:
    sys.exit(1)
EOF

echo "───────────────────────────────────────────────────────────────────────────"
if [ "${FAILURES}" -eq 0 ]; then
    echo "✓ All Swift static symbol, import & exclusivity quality gates passed cleanly!"
    exit 0
else
    echo "❌ Quality gate failed with ${FAILURES} error(s)."
    exit 1
fi
