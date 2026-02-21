# Technical Requirements Document: VoiceTyper

**Architecture Philosophy:**
VoiceTyper is a lightweight, headless macOS agent operating in the background. It consists of highly decoupled, single-responsibility modules orchestrating audio capture, local ML inference, and operating system event synthesis.

## Core Stack
- **Language:** Swift 6.0+
- **Platform:** macOS 13.0+ (Optimized for Apple Silicon / ARM64)
- **Engine Framework:** SPM (Swift Package Manager) building a native Executable Target.
- **ML Dependency:** `whisper.cpp` integrated via the `SwiftWhisper` package wrapper.

## System Components

### 1. Global Input Monitoring (`KeyboardListener`)
- **Mechanism:** Leverages Quartz Event Services (`CGEvent.tapCreate`).
- **Constraint:** Must bypass strict sandbox contexts by requiring system-level Accessibility permissions.
- **State Machine:** Governs precise timing logic for detecting `Hold`, `Release`, `Grace Period`, and `Double-tap Aborts` explicitly on the `Right Shift` (keycode `60`) physical key.

### 2. Audio Subsystem (`AudioRecorder`)
- **Mechanism:** Driven by `AVFoundation` (`AVAudioEngine`).
- **Data Shape:** Captures raw input directly from the hardware microphone, immediately resampled and normalized to single-channel (mono), 16kHz PCM Float arrays `[Float]`. This is strictly required by the whisper engine.
- **Optimization:** Processes RMS (Root Mean Square) energy levels dynamically to drop zero-volume arrays and achieve "Silence Rejection".

### 3. ML Inference Pipeline (`WhisperTranscriber`)
- **Mechanism:** Executes natively against `ggml` formatted bin models (e.g., `ggml-base.en.bin`).
- **Delivery:** Batch processing only. It receives the entire buffered audio sequence after the hotkey is fully released, processing the tensor weights entirely offline.

### 4. OS Event Synthesis (`TextInjector`)
- **Mechanism:** Dual-pronged injection strategy:
  1. *Animation:* Raw `CGEvent` emission to simulate granular backspace and character keystrokes for generating dynamic placeholder text (`processing...`).
  2. *Pasteback:* `NSPasteboard` manipulation to inject massive blocks of final transcribed text in <1ms via simulated `⌘+V` keystrokes.
- **Safety:** Mandates explicit preservation of the user's prior clipboard state, restoring it after exactly 500ms.

### 5. Deployment & Distribution
- **Distribution Model:** Raw script to clone, compile, and install via `make` and `bash`.
- **Model Fetching:** Automated URL fetching of pre-quantized `huggingface.co/ggerganov/whisper.cpp` ggml models using curl.
