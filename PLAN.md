# VoiceTyper Implementation Plan

## Active Tasks

- [x] **Plan 1 — Change Hotkey from Right Shift to Right Option** *(Priority: 🔴 High)*
- [ ] **Plan 2 — Hands-Free Voice Memory Logging & Session Handover into `memory` CLI** *(Priority: 🟡 Medium)*
- [x] **Plan 3 — Context-Aware Dynamic Vocabulary Injection via Memory Graph** *(Priority: 🟢 Low/Medium)*

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

# Plan 2 — Hands-Free Voice Memory Logging & Session Handover into `memory` CLI

## 1) Task Summary
- Module: `voicetyper/`
- Goal: Ingest transcribed speech notes, architectural decisions, and bug post-mortems directly into `memory` vault via dedicated shortcut chord (e.g. `Right Option + M`) and non-interactive CLI execution (`memory store`).
- Type: Integration feature
- Priority: Medium

## 2) Scope & Invariants
- Add a dedicated memory capture chord (e.g., holding `Right Option` while pressing `M` or double-tapping `M`) that flags the dictation buffer for memory ingestion rather than standard clipboard text injection.
- Transcribes audio locally using Whisper.cpp / Parakeet engine.
- Automatically routes output to non-interactive CLI:
  ```bash
  memory store "<Transcribed Content>" --type=conversation --tags="voice,memo,handover" --scope=project
  ```
- Optional automatic heuristic classification (`--type=decision` or `--type=learn` when keywords like "decision:" or "learned:" are detected in the spoken transcript).
- Preserves 100% offline-first privacy guarantees without cloud API dependencies.

---

# Plan 3 — Context-Aware Dynamic Vocabulary Injection via Memory Graph

## 1) Task Summary
- Module: `voicetyper/`
- Goal: Dynamically query the active `memory` graph / workspace glossary and bias the local Whisper speech decoder with project-specific terminology to eliminate phoneme hallucinations.
- Type: ML inference enhancement
- Priority: Low / Medium

## 2) Scope & Invariants
- Query active domain vocabulary from `memory` (e.g. OpenSCAD primitives `minkowski`, `translate`, `difference`; civil engineering terms `west_elevation`, `trench_z0`; DDD terms `aggregates`, `value_objects`).
- Pass extracted terminology into `whisper.cpp`'s initial prompt context buffer (`--prompt` token biasing) during model initialization or session start.
- Significantly improves transcription accuracy of code symbols, architecture jargon, and geodesy terms without requiring model fine-tuning or internet connectivity.
