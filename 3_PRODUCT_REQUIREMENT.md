# 3. Product Requirements Document: VoiceTyper

**Product Vision**
VoiceTyper is a privacy-first, zero-latency macOS dictation client that operates entirely on-device. It is built to seamlessly translate rapid thought into typed text without depending on internet connectivity, third-party APIs, or subscription costs.

**Target Audience**
Power users, rapid typers, developers, and writers seeking an offline macOS speech-to-text solution that works anywhere they can type.

---

## 1. Core User Workflows

### 1.1 Triggering Dictation (Hold-to-Talk)
- Users interact solely through a global hardware hotkey (`Right Option`).
- Dictation begins immediately upon depressing the key. 
- A translucent oscillating microphone overlay appears at the bottom center of the active screen, accompanied by a `🔴` icon in the system menu bar to indicate active listening.

### 1.2 Transcription & Insertion
- Upon releasing the hotkey, the microphone overlay hides.
- The app emits an animated `processing...` typographic feedback loop directly into the user's active cursor location (text field/window). The menu bar swaps to an hourglass `⏳`.
- Inference occurs locally. Once completed, the placeholder text is smoothly erased and the AI-transcribed output is injected instantaneously via global clipboard paste manipulation.
- A trailing space is automatically appended to enable seamless continuous typing flows.

---

## 2. Advanced UX Behaviors

### 2.1 Grace Period (Stutter Prevention)
- Users commonly pause to breathe or think. Releasing the hotkey and depressing it again within exactly < 400ms prevents the sentence from dividing into two. The application seamlessly stitches the audio frames together.

### 2.2 Silence Rejection
- If a user inadvertently depresses the hotkey but generates zero audible speech, the application instantly terminates the workflow upon release, preventing the insertion of blank or hallucinated audio tokens into text fields.

---

## 3. Mitigation & Abort Workflows

### 3.1 Hard Abort Audio (Double-Tap)
- **Trigger:** Rapidly double-tapping the `Right Option` hotkey during dictation.
- **Action:** Trashes the auditory buffer and cancels the sequence immediately before transcription inference is allowed to begin.

### 3.2 Terminate Processing (Force Escape)
- **Trigger:** Pressing `Control + C` on the keyboard while the AI is transcribing (and the `processing...` animation is playing).
- **Action:** Instantly halts the animation, clears the visual `processing...` placeholder, discards the eventual ML output, and returns control to the user.

### 3.3 UI Hard Abort (Mouse Click)
- **Trigger:** Clicking the floating `🔴` recording indicator window at the bottom of the screen with a mouse/trackpad pointer.
- **Action:** Forcefully aborts any ongoing recording, dumps active buffers, stops animations, and resets the listener state, serving as a reliable failsafe for stuck software/hardware key states.

---

## 4. State & Privacy 

### 4.1 Clipboard Preservation
- Since VoiceTyper temporarily commandeers macOS's copy-paste buffer to instantly inject large blocks of text, it must implicitly memorize and restore whatever data the user had in their clipboard prior to the sequence.

### 4.2 Offline ML Ecosystem
- All voice data must be ingested and inferred directly against `.bin` weight files via an offline ML loop. The application defaults to downloading and loading the `ggml-base.en.bin` (~142MB) model locally.
- Provides fallback configurability via an `.xcconfig` file for loading alternative quantized constraints.

---

## 5. Universal Memory Vault Integration

### 5.1 Hands-Free Voice Memory Logging & Live Session Handover
- **ML Processing Pipeline**: Leverages VoiceTyper's on-device `llama.cpp` / `parakeet` / `whisper` inference engines to transcribe spoken developer thoughts, architectural decisions, bug learnings, and standup updates.
- **Dedicated Shortcut Chord**: Activating `Right Option + M` (or double-tapping `M` during dictation) directs the transcribed stream into the background `memory` vault rather than pasting into the active text field.
- **Direct CLI Ingestion**: Automatically dispatches transcribed text to the `memory` CLI with heuristic classification:
  ```bash
  memory store "<Transcribed Content>" --type=conversation --tags="voice,memo,handover" --scope=project
  ```
  - If the transcript begins with "decision:" or "decided:", automatically tags `--type=decision`.
  - If the transcript begins with "learned:" or "rule:", automatically tags `--type=learn`.
- **Associative Recall**: Transcribed speech memos become instantly recallable by AI coding agents via `memory recall` and `memory thread`.

### 5.2 Context-Aware Dynamic Vocabulary Injection
- **Problem**: Technical jargon (e.g., OpenSCAD functions `minkowski()`, DDD patterns `aggregate_root`, geodesy landmarks `west_elevation`) often suffers phoneme degradation in generic offline Whisper models.
- **Memory Glossary Biasing**: On startup or workspace switch, VoiceTyper queries the active `memory` graph / glossary terms.
- **Prompt Token Biasing**: Dynamically seeds `whisper.cpp`'s `--prompt` context buffer with project-specific terminology, drastically improving speech-to-code accuracy without fine-tuning models.

---

## 6. Swift Quality Gates & Crash Prevention

### 6.1 Safe C-Bridge Memory Management & Zero Force Unwraps (`SWIFT-01`)
- **SAFE-C-01**: `ParakeetTranscriber` and all C-interop bindings must strictly prohibit force unwrapping (`!`) on nullable C memory pointers (`strdup`, `malloc`, C struct handles).
- **SAFE-C-02**: All C pointer duplication must be guarded by safe conditional unwrapping with throwing domain errors:
  ```swift
  guard let ptr = strdup(str) else {
      throw TranscriberError.outOfMemory("Failed to duplicate C string buffer")
  }
  ```
- **SAFE-C-03**: Prohibit silent error suppression (`try?`) on disk archiving operations (`saveConversation`); all I/O errors must be explicitly caught and logged with structured diagnostics.
- **SAFE-C-04**: Maintain strict `@MainActor` isolation across all asynchronous UI animations and downloader managers to guarantee thread safety.

---

## 7. Native Audio DSP & Spectral Noise Sanitization (`AUDIO-DSP-01`)

### 7.1 Dual-Stage Classical DSP Pipeline
- **4th-Order 80Hz Butterworth High-Pass Filter**: Automatically strips 50Hz/60Hz AC electrical mains hum, keyboard clatter, and laptop fan rumble with a sharp -24dB/octave slope.
- **Stationary Spectral Subtraction with Spectral Floor**: Uses vectorized FFT (`Accelerate` / `vDSP`) to calculate ambient noise profiles from baseline frames and subtract them with a proportional floor (`prop_decrease = 0.75`, `spectralFloor = 0.05`), ensuring natural vocal timbre without metallic or robotic distortion.

### 7.2 Pre-Inference Audio Sanitization Guarantee
- **Model Ingestion**: Both Whisper and Parakeet receive pre-sanitized audio frames, eliminating false triggers and ambient-pause hallucination tokens (`[Music]`, `Thank you`).
- **Archive Fidelity**: Saved `.wav` conversation memos (`~/.voicetyper/conversation/<YYYY-MM-DD>/audio/*.wav`) are stored in crystal-clear studio fidelity.
- **Accuracy Improvement**: Reduces Word Error Rate (WER) by 15% to 35% in real-world laptop environments with active cooling fans or background room noise.

### 7.3 Native Apple Voice Processing IO
### 7.4 Adaptive Speech Gain & Peak Normalization with Soft-Knee Limiter
- **Problem**: Low microphone hardware input volumes or users speaking softly caused quiet recordings, low audio playback, and slow Whisper beam convergence.
- **SIMD Peak Detection**: Uses Apple Accelerate `vDSP_maxmgv` to measure absolute peak signal amplitude.
- **Dynamic Gain Boost**: Scales audio up to `+18 dB` (8.0x gain factor) targeting `-1.0 dBFS` (`0.89` linear peak headroom).
- **Soft-Knee Saturation Limiter**: Implements a smooth hyperbolic tangent ($\tanh$) ceiling above $0.85$ to ensure 0% digital clipping or harsh harmonic distortion.
- **Transcription Acceleration**: Pre-normalized speech converges Whisper decoding 15% to 25% faster.

---

## 8. Single-Instance Architecture & Zero-Sudo Self-Upgrade

### 8.1 Single-Instance Enforcement (`PID-01`)
- The application guarantees exactly **one** microphone tray icon in the macOS menu bar via atomic PID locking (`~/.voicetyper/voicetyper.pid`).
- Duplicate or orphaned processes are automatically terminated on startup (`kill(oldPID, SIGTERM)`).

### 8.2 Unified Native Menu Bar Layout
- 100% native Apple AppKit `NSMenu` with clean indentation padding (`indentationLevel = 1`) and zero emoji clutter.
- Reorganized Top-Down Hierarchy:
  - **Section 1**: `Show VoiceTyper (⌘H)` + `Open Daily Vault Folder`.
  - **Section 2**: `Mode:` with checkmarks (`✓ Smart Dual`, `Direct Dictation Only`, `Hands-Free Memo Only`).
  - **Section 3**: `Select Whisper Model ▶` flyout submenu with model sizes and download states; `Check for Updates...`; `Quit VoiceTyper (⌘Q)`.

### 8.3 Zero-Sudo User-Space Upgrades
- Binary installed to user-owned `$HOME/.local/bin/voicetyper` to completely eliminate `sudo` password prompts and terminal hangs during self-upgrades (`voicetyper upgrade`).
- Self-upgrade renders ANSI Cyan FIGlet ASCII branding matching the unified developer tooling suite.

---

## 9. Hands-Free Conversation Capture & Rolling Laps Engine (`CONV-LAP-01`)

### 9.1 Hands-Free Toggle Workflow (No Holding Required)
- **1st Tap (`Shift + Right Option`)**: Starts conversation capture mode. The user can immediately release the keyboard and conduct long-form discussions, meetings, or voice memos hands-free.
- **2nd Tap (`Shift + Right Option`)**: Wraps up and saves the conversation recording (protected by a 350ms debounce threshold to prevent accidental double-tap closures).
- **Direct Dictation Coexistence**: Rapid inline typing (`Right Option` alone) remains **Hold-to-Talk**, ensuring zero friction for quick 3-second cursor dictations.

### 9.2 Rolling 5-Minute Laps (Zero Memory Overflow)
- **Chunking Interval**: Automatically rolls over every **5 minutes (300 seconds)** without interrupting active microphone capture.
- **Part-Based Archiving**: Lap 1 flushes as `conversation_<timestamp>_part1.wav` + `part1.txt` and immediately begins background Whisper transcription. Lap 2 begins recording seamlessly in a fresh buffer.
- **Data Safety**: Total RAM remains bounded at $< 40\text{MB}$ at all times. If power cuts or the laptop lid closes, all previous 5-minute segments are safely persisted to disk.

### 9.3 1-Minute Silence Auto-Stop Safeguard
- **Idle Silence Detection**: If ambient audio remains below threshold (RMS < 0.005) for **continuous 60 seconds (1 minute)**, VoiceTyper automatically concludes and saves the recording.
- **Disk Protection**: Eliminates recording hours of empty room silence if the user walks away without stopping.

### 9.4 Dual-Mode Floating Indicator
- **Direct Dictation Mode (`.standard`)**: Minimalist 34x34px coral pink circle (`#FD7979`) with breathing opacity pulse (`1.0 ⟷ 0.35`).
- **Conversation Mode (`.memoryVault`)**: Symmetrical 136x34px purple pill (`#A855F7`):
  ```text
  ╭─────────────────────────────────╮
  │  🎙️  |||||  01  │  04:28       │
  ╰─────────────────────────────────╯
  ```
  * `🎙️`: Centered white microphone icon.
  * `|||||`: **Live 5-bar signal-reactive waveform EQ** animated in real-time by normalized RMS microphone power (`AudioRecorder.onAudioLevel`).
  * `01`: 2-digit monospaced lap number (`01`, `02`, `03`...).
  * `│`: 1px subtle translucent separator.
  * `04:28`: Live ticking elapsed timer updating second-by-second.
  * **Click-to-Stop**: Entire pill is clickable to immediately wrap up and save the recording.

---

## 10. Automated Swift Symbol & Exclusivity Quality Gates (`GATE-01`)

### 10.1 Static AST & Exclusivity Gate (`tests/verify_symbols.sh`)
- **Automated Execution**: Runs as the first quality gate in `make test` before compilation.
- **Framework Import Verification**: Verifies `import Cocoa` and `import Foundation` across all AppKit and Darwin entrypoints.
- **Duplicate Property Inspector**: Verifies zero duplicate `let`/`var` property declarations within class definitions.
- **Swift Memory Exclusivity Guarantee**: Ensures all `withUnsafeMutableBufferPointer` blocks mutate pointers (`realPtr[k]`) rather than enclosing array variables (`real[k]`), preventing `#ExclusivityViolation` errors.
- **Temporary Pointer Prevention**: Rejects raw inout `&array` arguments in struct initializers (`DSPSplitComplex`).
- **2-Pass Cross-File Type-Stack Symbol & Access-Level Validation**:
  - *Pass 1*: Indexes all classes, structs, enums, extensions, member methods, and visibility modifiers (`private`, `fileprivate`, `internal`, `public`).
  - *Pass 2*: Validates all member call-sites across files, catching non-existent members and access-control violations before commit.




