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
- Integrates macOS CoreAudio Voice Processing IO (`isVoiceProcessingEnabled = true`) on `AVAudioEngine.inputNode` for hardware-accelerated Acoustic Echo Cancellation (AEC) and Automatic Gain Control (AGC).

---

## 8. Single-Instance Architecture & Zero-Sudo Self-Upgrade

### 8.1 Single-Instance Enforcement (`PID-01`)
- The application guarantees exactly **one** microphone tray icon in the macOS menu bar via atomic PID locking (`~/.voicetyper/voicetyper.pid`).
- Duplicate or orphaned processes are automatically terminated on startup (`kill(oldPID, SIGTERM)`).

### 8.2 Unified Multi-Mode Switcher
- **Smart Dual Mode (Default)**: `Right Option` triggers Direct Dictation (injected at cursor); `Shift + Right Option` triggers Conversation Capture (saved as date-grouped `.wav` + `.txt`).
- **Direct Dictation Only**: Forces all hotkeys to type at the cursor.
- **Conversation Capture Only**: Forces all hotkeys to record structured voice memos.

### 8.3 Zero-Sudo User-Space Upgrades
- Binary installed to user-owned `$HOME/.local/bin/voicetyper` to completely eliminate `sudo` password prompts and terminal hangs during self-upgrades (`voicetyper upgrade`).



