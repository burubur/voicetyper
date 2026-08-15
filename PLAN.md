# VoiceTyper Implementation Plan

## Active Tasks

- [x] **Plan 1 — Change Hotkey from Right Shift to Right Option** *(Priority: 🔴 High)*
- [ ] **Plan 2 — Voice Memory & Spoken Standup Ingestion into `memory` CLI** *(Priority: 🟡 Medium)*

---

# Plan 1 - Change Hotkey from Right Shift to Right Option

## 1) Task Summary
- Module: `voicetyper/`
- Goal: Change global hold-to-talk hotkey from Right Shift (`keyCode 0x3C` / 60) to Right Option (`keyCode 0x3D` / 61).
- Type: feature modification
- Priority: High

## 2) Background & Links
- Primary modifier handling in `Sources/VoiceTyper/KeyboardListener.swift`.
- Menu bar & logger in `Sources/VoiceTyper/App.swift`.
- Window status label in `Sources/VoiceTyper/TranscriptionHistoryWindowController.swift`.
- Product and specs documentation (`README.md`, `1_PRODUCT_BRIEF.md`, `2_SPECIFICATION_BRIEF.md`, `3_PRODUCT_REQUIREMENT.md`, `4_TECHNICAL_SPECIFICATION.md`, `5_TEST_SCENARIOS.md`).

## 3) Scope & Constraints
- In scope:
  - Keycode update to `0x3D` (`kVK_RightOption`).
  - Flag update to `.maskAlternate` (Option/Alt key).
  - Hardware device bitmask update to `0x00000040` (`NX_DEVICERALTKEYMASK` / `NX_DEVICEROPTIONKEYMASK`).
  - Logging, accessibility prompt, UI status labels, and documentation updates.
- Out of scope:
  - Audio recording logic, transcriber interfaces, or text injection mechanism.

## 4) Acceptance Criteria
- `KeyboardListener.swift` handles Right Option (`0x3D`, `.maskAlternate`, device mask `0x40`) for press, hold, release, double-tap abort, and grace period handling.
- `App.swift` and `TranscriptionHistoryWindowController.swift` display "Right Option and hold to record".
- Code compiles cleanly with Swift compiler (`swift build`).
- Documentation updated to reference Right Option.

## 5) Implementation Plan
1. Edit `KeyboardListener.swift` to update keycode constants, flags, masks, and strings.
2. Edit `App.swift` to update prompt message.
3. Edit `TranscriptionHistoryWindowController.swift` to update status label string.
4. Update product & specification docs.
5. Build and verify using Swift CLI (`swift build`).

---

# Plan 2 — Voice Memory & Spoken Standup Ingestion into `memory` CLI

## 1) Task Summary
- Module: `voicetyper/`
- Goal: Ingest transcribed speech notes and audio memos directly into `memory` vault via CLI execution (`memory store --type=conversation`).
- Type: Integration feature
- Priority: Medium

## 2) Scope & Invariants
- Uses local `llama.cpp` / `parakeet` / `whisper` inference models.
- Invokes `memory store "<content>" --type=conversation --conversation-id="<id>" --tags="voice,memo"` non-interactively.
- Preserves offline-first privacy guarantees.
