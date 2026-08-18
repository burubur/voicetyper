# VoiceTyper Implementation Plan

## Active Tasks

- [x] **Plan 1 — Change Hotkey from Right Shift to Right Option** *(Priority: 🔴 High)*
- [x] **Plan 2 — Hands-Free Voice Memory Logging (`Shift + Right Option`) & Local Conversation Archiving** *(Priority: 🟡 Medium)*
- [x] **Plan 3 — Context-Aware Dynamic Vocabulary Injection via Memory Graph** *(Priority: 🟢 Low/Medium)*
- [x] **Plan 4 — Native Classical Audio DSP Noise Sanitization (80Hz Butterworth + Spectral Subtraction)** *(Priority: 🔴 High)*
- [x] **Plan 5 — Hands-Free Conversation Capture, Rolling 5-Minute Laps & 1-Minute Silence Auto-Stop** *(Priority: 🔴 High)*
- [x] **Plan 6 — Signal-Reactive 5-Bar Waveform EQ & Circular Minimalist Indicator** *(Priority: 🔴 High)*
- [x] **Plan 7 — Native Padded macOS Menu Bar Reorganization (`Show VoiceTyper`, `Mode:`, `Select Whisper Model ▶`)** *(Priority: 🔴 High)*
- [x] **Plan 8 — Audio DSP Adaptive Speech Gain & Peak Normalization with Soft-Knee Limiter** *(Priority: 🔴 High)*
- [x] **Plan 9 — Studio Window UI Unification, Hover Actions & Strict Card Bounding** *(Priority: 🔴 High)*
- [x] **Plan 10 — 2-Pass Cross-File Static Symbol & Access-Level Quality Gate** *(Priority: 🔴 High)*

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

# Plan 2 — Hands-Free Voice Memory Logging (`Shift + Right Option`) & Local Conversation Archiving

## 1) Task Summary
- Module: `voicetyper/`
- Goal: Record voice conversation memos via dedicated modifier chord (`Shift + Right Option`), saving raw 16kHz mono WAV audio clips to `~/.voicetyper/conversation/audio/` and transcribed text to `~/.voicetyper/conversation/text/`, without typing into or modifying the active cursor/clipboard.
- Type: Feature & Storage module
- Priority: Medium

## 2) Scope & Invariants
- Dual-mode keystroke detection in `KeyboardListener.swift`:
  - `Right Option` alone $\rightarrow$ `.standard` dictation (pastes to active window).
  - `Shift + Right Option` $\rightarrow$ `.memoryVault` mode (archives audio WAV + text without cursor pasting).
- `VoiceConversationStorage.swift`:
  - Automatically ensures `~/.voicetyper/conversation/audio/` and `~/.voicetyper/conversation/text/` exist.
  - Encodes captured Float PCM frames into compliant 16-bit mono 16kHz WAV format (`conversation_<timestamp>_<id>.wav`).
  - Writes transcribed UTF-8 text (`conversation_<timestamp>_<id>.txt`).
- `MemoryVaultIngester.swift`:
  - Heuristic intent classifier for decision, learn, rule, fact, and standup tags.
- Visual HUD feedback:
  - `FloatingRecordingIndicator.swift` displays a purple brain indicator (`🧠 🔴`) during memory recording.
- Preserves 100% offline privacy and clipboard invariants.

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

---

# Plan 4 — Native Classical Audio DSP Noise Removal

## 1) Task Summary
- Module: `Sources/VoiceTyper/AudioDSP.swift`
- Goal: Implement real-time Apple Accelerate vDSP 4th-order 80Hz Butterworth high-pass filter and stationary spectral subtraction to eliminate 50/60Hz mains hum, keyboard clicks, and fan noise before Whisper inference.
- Type: Audio DSP Engine
- Priority: High

## 2) Scope & Acceptance
- Cascaded biquad IIR filter attenuates frequencies $<80\text{Hz}$ with $-24\text{dB/octave}$ slope.
- Real-to-complex FFT with Hann windowing, noise floor estimation, and spectral subtraction ($\alpha = 0.75, \beta = 0.05$).
- Reconstructs clean signal via Overlap-Add (OLA) in $<2\text{ms}$.
- Verified against unit tests (`AudioDSPTests.swift`) and real-world audio memo samples.

---

# Plan 5 — Hands-Free Conversation Capture, Rolling Laps & Silence Auto-Stop

## 1) Task Summary
- Module: `ConversationLapManager.swift`, `KeyboardListener.swift`, `FloatingRecordingIndicator.swift`
- Goal: Support hands-free toggle recording for long conversations with 5-minute rolling chapter segmentation, 1-minute silence auto-stop, and an ultra-compact minimalist floating pill.
- Type: UX & Core Engine
- Priority: High

## 2) Scope & Acceptance
- 1st tap on `Shift + Right Option` starts hands-free recording; 2nd tap stops & saves.
- Automatic 5-minute rollover flushes Lap $N$ to `conversation_<timestamp>_<id>_partN.wav`, kicks off background transcription, and continues Lap $N+1$ recording seamlessly.
- Continuous 60s silence (RMS < 0.005) automatically concludes session to protect storage.
- Floating indicator renders minimal 92x28px pill (`🟣 01 │ 04:28`).
- Static AST quality gate `tests/verify_symbols.sh` integrated into `make test`.

---

# Plan 6 — Signal-Reactive 5-Bar Waveform EQ & Circular Minimalist Indicator

## 1) Task Summary
- Module: `Sources/VoiceTyper/FloatingRecordingIndicator.swift`, `Sources/VoiceTyper/AudioRecorder.swift`
- Goal: Separate floating indicator into a minimalist pink circle for direct dictation, and a signal-reactive 5-bar EQ waveform meter inside a symmetrical purple pill for conversation memos.
- Type: UI / Real-Time Audio Visualization
- Priority: High

## 2) Scope & Acceptance
- Direct dictation (`.standard`): `34x34px` pink circle (`#FD7979`), centered white mic icon, breathing opacity animation (`1.0 ⟷ 0.35`).
- Conversation memo (`.memoryVault`): `136x34px` purple pill (`#A855F7`), white mic icon, 5 vertical bars dynamically animated via normalized RMS power emitted by `AudioRecorder.onAudioLevel`, lap counter (`01`), divider (`│`), and ticking elapsed timer (`00:00`).
- All sub-elements vertically centered using AutoLayout `centerYAnchor`.

---

# Plan 7 — Native Padded macOS Menu Bar Reorganization

## 1) Task Summary
- Module: `Sources/VoiceTyper/App.swift`
- Goal: Revert custom popover to 100% native Apple AppKit `NSMenu` with icon-free typography, standard indentation padding (`indentationLevel = 1`), and reorganized top-down section ordering.
- Type: UI / Menu Bar Architecture
- Priority: High

## 2) Scope & Acceptance
- Section 1 (Top): `Show VoiceTyper (⌘H)` + `Open Daily Vault Folder`.
- Section 2 (Middle): `Mode:` with checkmarks (`✓ Smart Dual`, `Direct Dictation Only`, `Hands-Free Memo Only`).
- Section 3 (Bottom): `Select Whisper Model ▶` flyout submenu with model size descriptions & download states; `Check for Updates...`; `Quit VoiceTyper (⌘Q)`.
- Zero emojis and zero background popover lag.

---

# Plan 8 — Audio DSP Adaptive Speech Gain & Peak Normalization

## 1) Task Summary
- Module: `Sources/VoiceTyper/AudioDSP.swift`, `notebooks/noise_reduction_prototype.ipynb`, `tests/test_audio_dsp_gain.py`
- Goal: Fix low-volume microphone recordings by adding Adaptive Speech Gain and Dynamic Peak Normalization with a Soft-Knee Saturation Limiter.
- Type: Audio DSP / Speech Enhancement
- Priority: High

## 2) Scope & Acceptance
- Fast SIMD peak detection using Apple Accelerate `vDSP_maxmgv`.
- Dynamic gain boost scaling quiet speech by up to `+18 dB` (8.0x) targeting `-1.0 dBFS` (`0.89`) peak headroom.
- Soft-knee hyperbolic tangent ($\tanh$) limiter above $0.85$ to ensure 0% digital clipping.
- Interactive Google Colab notebook updated with audio players and spectrogram comparisons.
- Speeds up Whisper transcription by 15–25% due to faster beam decoder convergence.

---

# Plan 9 — Studio Window UI Unification & Strict Card Bounds

## 1) Task Summary
- Module: `Sources/VoiceTyper/TranscriptionHistoryWindowController.swift`
- Goal: Unify card action toolbars across Transcriptions and Conversations tabs with hover-to-reveal icon buttons, strict height constraints, and ellipsis truncation.
- Type: UI / Window Controller
- Priority: High

## 2) Scope & Acceptance
- Sub-Header Bar: Vault directory path + compact `[ 🔄 ]` refresh + icon-only `[ 📁 ]` Finder button.
- Transcription Cards: Bounded height (`110pt ≤ height ≤ 160pt`), max 4 lines with ellipsis, bottom-row date/time + hover-to-reveal `[ 📋 Copy ]` and `[ 🗑 Delete ]` buttons.
- Conversation Cards: Bounded height (`110pt ≤ height ≤ 150pt`), max 3 lines with ellipsis, bottom-row date/time + hover-to-reveal `[ ▶ Play ]`, `[ 📁 Finder ]`, and `[ 🗑 Delete ]` buttons.

---

# Plan 10 — 2-Pass Static Symbol & Access-Level Quality Gate

## 1) Task Summary
- Module: `tests/verify_symbols.sh`, `Makefile`
- Goal: Prevent compilation and access-level regressions in Linux container environments lacking Apple SDKs.
- Type: CI / Pre-Commit Quality Gate
- Priority: High

## 2) Scope & Acceptance
- Pass 1 (Type-Stack Symbol Table): Indexes all classes, structs, enums, extensions, methods, properties, and access levels (`private`, `internal`, `public`).
- Pass 2 (Call-Site & Visibility Validation): Validates all member invocations across files, failing `make test` on non-existent members or `private` access-level violations.
- Verified and stored in project memory vault (`[p:mem_1787017004962241005]`).


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

# Plan 2 — Hands-Free Voice Memory Logging (`Shift + Right Option`) & Local Conversation Archiving

## 1) Task Summary
- Module: `voicetyper/`
- Goal: Record voice conversation memos via dedicated modifier chord (`Shift + Right Option`), saving raw 16kHz mono WAV audio clips to `~/.voicetyper/conversation/audio/` and transcribed text to `~/.voicetyper/conversation/text/`, without typing into or modifying the active cursor/clipboard.
- Type: Feature & Storage module
- Priority: Medium

## 2) Scope & Invariants
- Dual-mode keystroke detection in `KeyboardListener.swift`:
  - `Right Option` alone $\rightarrow$ `.standard` dictation (pastes to active window).
  - `Shift + Right Option` $\rightarrow$ `.memoryVault` mode (archives audio WAV + text without cursor pasting).
- `VoiceConversationStorage.swift`:
  - Automatically ensures `~/.voicetyper/conversation/audio/` and `~/.voicetyper/conversation/text/` exist.
  - Encodes captured Float PCM frames into compliant 16-bit mono 16kHz WAV format (`conversation_<timestamp>_<id>.wav`).
  - Writes transcribed UTF-8 text (`conversation_<timestamp>_<id>.txt`).
- `MemoryVaultIngester.swift`:
  - Heuristic intent classifier for decision, learn, rule, fact, and standup tags.
- Visual HUD feedback:
  - `FloatingRecordingIndicator.swift` displays a purple brain indicator (`🧠 🔴`) during memory recording.
- Preserves 100% offline privacy and clipboard invariants.

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

---

# Plan 4 — Native Classical Audio DSP Noise Removal

## 1) Task Summary
- Module: `Sources/VoiceTyper/AudioDSP.swift`
- Goal: Implement real-time Apple Accelerate vDSP 4th-order 80Hz Butterworth high-pass filter and stationary spectral subtraction to eliminate 50/60Hz mains hum, keyboard clicks, and fan noise before Whisper inference.
- Type: Audio DSP Engine
- Priority: High

## 2) Scope & Acceptance
- Cascaded biquad IIR filter attenuates frequencies $<80\text{Hz}$ with $-24\text{dB/octave}$ slope.
- Real-to-complex FFT with Hann windowing, noise floor estimation, and spectral subtraction ($\alpha = 0.75, \beta = 0.05$).
- Reconstructs clean signal via Overlap-Add (OLA) in $<2\text{ms}$.
- Verified against unit tests (`AudioDSPTests.swift`) and real-world audio memo samples.

---

# Plan 5 — Hands-Free Conversation Capture, Rolling Laps & Silence Auto-Stop

## 1) Task Summary
- Module: `ConversationLapManager.swift`, `KeyboardListener.swift`, `FloatingRecordingIndicator.swift`
- Goal: Support hands-free toggle recording for long conversations with 5-minute rolling chapter segmentation, 1-minute silence auto-stop, and an ultra-compact minimalist floating pill.
- Type: UX & Core Engine
- Priority: High

## 2) Scope & Acceptance
- 1st tap on `Shift + Right Option` starts hands-free recording; 2nd tap stops & saves.
- Automatic 5-minute rollover flushes Lap $N$ to `conversation_<timestamp>_<id>_partN.wav`, kicks off background transcription, and continues Lap $N+1$ recording seamlessly.
- Continuous 60s silence (RMS < 0.005) automatically concludes session to protect storage.
- Floating indicator renders minimal 92x28px pill (`🟣 01 │ 04:28`).
- Static AST quality gate `tests/verify_symbols.sh` integrated into `make test`.
