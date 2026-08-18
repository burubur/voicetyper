# 4. Technical Specification: VoiceTyper

**Architecture & Frameworks**
VoiceTyper revolves around a native, headless background agent architecture tightly integrated with low-level macOS subsystems and a lightweight floating/history GUI layer. This Low-Level Design (LLD) document outlines the granular engineering specifications, hardware integrations, and concurrency boundaries executed across the codebase.

---

## 1. Core Operating Environment
- **Object Context:** Built on the macOS `NSApplicationDelegate` lifecycle, controlling system tray status items and a native `TranscriptionHistoryWindowController` window interface.
- **System Interface:** Registers an `NSStatusItem` in the system menu bar bridging system-tray status changes (🎙️, 🔴, ⏳) back to the internal state machine and providing model selector menus.
- **Permissions Topology:**
  - **Accessibility** (`AXIsProcessTrustedWithOptions`): Mandated to silently intercept and construct global generic keystrokes (`CGEvent` `tapCreate`) without breaking sandbox security.
  - **Microphone** (`kTCCServiceMicrophone`): Mandated to allocate raw hardware `AVAudioEngine` node taps in the background process.

---

## 2. Global Input Supervisor (`KeyboardListener.swift`)
- **Event Tap:** Installs a `.cgSessionEventTap` at `.headInsertEventTap` location. Filters purely for `.flagsChanged` and `.keyDown`.
- **Primary Trigger (Dictation):** Tracks physical hardware keycode `0x3D` (`Right Option`). Filters logic by inspecting the `.maskAlternate` bit flag and device-specific mask (`0x40`). 
- **Time/State Machine Logic:**
  - **Grace Timer:** An autonomous `DispatchSourceTimer` scheduled dynamically on the main queue to grant a `0.8s` grace period after key release, stitching multi-breath recordings.
  - **Double-Tap Abort:** Determines precise `processInfo.systemUptime` deltas. If `timeSinceLastRelease < 0.3s` and `timeSinceLastPress < 0.6s`, the sequence abruptly triggers a panic tear-down and discards the memory buffer.
- **Escape Route (`Ctrl + C`):** Sniffs precisely for `.keyDown` keycode `0x08` (C) coupled with the `.maskControl` flag. Bypasses grace timers and instantly destroys active AI rendering tasks via `@MainActor`.

---

## 3. Audio Subsystem (`AudioRecorder.swift`)
- **Hardware Integration:** Allocates the default microphone via `AVAudioEngine.inputNode`. Installs a direct `installTap(bufferSize: 4096)` to circumvent writing arbitrary temporal files to disk.
- **Dynamic Downsampling:** Whisper inference demands precisely `16000.0` sample rates. The audio subsystem parses `AVAudioPCMBuffer` sizes entirely in memory. If upstream hardware exceeds `16kHz`, it executes manual floating-point mathematical linear resampling interpolation array mapping across the payload down to the target dimension.
- **Silence Mitigation Constraints:** Validates against `minimumFrameCount = 4800` (roughly 0.3 seconds). Anything less is inherently rejected as ghost touches, optimizing GPU/CPU cycles.

---

## 4. ML Inference Engine (`WhisperTranscriber.swift` & `SwiftWhisper`)
- **Wrapper Paradigm:** Complies with a generic `Transcriber` Swift protocol abstraction, funneling down to `whisper.cpp` neural bindings wrapped by Swift Package `SwiftWhisper` mapping over C++.
- **Hardware Weight Bindings & Model Management:** Inspects macOS `UserDefaults`, local `.xcconfig`, environment variables, or menu bar selections to load `.bin` tensors from `~/.voicetyper/`. Supports asynchronous background downloading via `URLSessionDownloadDelegate`. Defaults strictly to loading `ggml-base.en.bin` (~142MB).
- **Hallucination Pruning:** Inherently drops and cleans known Whisper AI artifact patterns mathematically proven as void loops (e.g., `"[BLANK_AUDIO]"`, `"Thank you."`, `"(silence)"`). 

---

## 5. OS Event Synthesis (`TextInjector.swift`)
Deploys a dual-phased OS injection layer to offset heavy tensor-calculation lag while ensuring a zero-latency UX illusion.
1. **Dynamic Visualization (CGEvent Emission):** 
   - Queues a virtual hardware `CGEvent` string via `.cghidEventTap`. 
   - Wraps a Swift `Task` loop emitting `"processing"`, stepping through sequential literal `"..."` periods paused securely via `Task.sleep(nanoseconds: 500_000_000)`. 
   - Synthesizes iterative `0x33` (`kVK_Delete` / backspace) sequences to magically erase the placeholder from the user's GUI precisely upon AI fulfillment.
2. **Deterministic Delivery (NSPasteboard Injection):** 
   - Instantiates `NSPasteboard.general`. Copies the explicit multi-type payload existing prior.
   - Assigns the AI string inference payload. Synthesizes a virtual `.maskCommand` coupled with `<key 0x09>` (`V`) using the hardware tap point.
   - Triggers an asynchronous queue `0.5s` later resetting memory to restore the original copyboard history, averting destructive state-loss.

---

## 6. Floating Visual UX (`FloatingRecordingIndicator.swift`)
- **Window Level:** Generates an invisible `NSWindow` marked as `.borderless`, `.floating`, sitting structurally separated above every native macOS application canvas.
- **Geometry Coordinates:** Calculates exact bottom-center `NSPoint(x, y)` relative dynamically to `screen.visibleFrame.midX` and `.minY + 40.0` preventing dock occlusions.
- **Render Compositor & Abort Interaction:**
  - Instantiates pure `CALayer` and CoreGraphic contexts overlapping native SF Symbols (`mic.fill`). 
  - Subscribes `CABasicAnimation` key paths mutating contextual opaque background elements sequentially with `CAMediaTimingFunction` set globally as `.easeInEaseOut` for an infinite pulsating loop effect.
  - Exposes an interactive `onAbort` callback linked to `KeyboardListener.forceAbort()` to discard active recordings when clicked.

---

## 7. History & Settings UI (`TranscriptionHistoryWindowController.swift`)
- **Window Management:** Controls an `NSWindow` hosting a native SwiftUI/AppKit interface accessible via the system status bar menu ("Show VoiceTyper").
- **State Store:** Maintains an in-memory collection of recent transcription history records, allowing single-click copy operations, quick re-transcription triggers, and model switching menus.

---

## 8. App Concurrency & Confinement
- **Actor Boundaries:** `KeyboardListenerDelegate` invocations bind `Recording`, `Stopping`, and `Injection` actions strictly to the `@MainActor`. 
- **Wait Queues:** Heavy AI `.transcribe()` tasks run decoupled in `.background` Task pipelines. Prevents threading-locking and explicitly manages single-channel pipeline bottlenecks (`self.transcriptionTask?.result`) to stop SwiftWhisper instance crashes.
- **StdErr Piping:** Uses POSIX `dup2` to bind `/dev/null` towards FileDescriptor `2` natively hiding noisy underlying C++ ML `stderr` outputs internally unless initialized explicitly via terminal via the `--debug` parameter struct path.

---

## 9. Audio DSP Engine (`AudioDSP.swift`)
- **High-Pass Filter:** 4th-order cascaded biquad Direct Form II Butterworth filter ($f_c = 80\text{ Hz}$, $f_s = 16000\text{ Hz}$, $Q_1 = 0.5412$, $Q_2 = 1.3066$) for -24dB/octave low-frequency roll-off.
- **Vectorized Spectral Subtraction:**
  - $N=512$ FFT windowing with 50% overlap ($H=256$) using Apple `Accelerate` `vDSP_hann_window`, `vDSP_fft_zrip`, and `vDSP_zvabs`.
  - Noise floor estimation via lowest-energy baseline frames.
  - Spectral subtraction with over-subtraction factor $\alpha = 0.75$ and spectral floor $\beta = 0.05$.
  - Reconstructed via Overlap-Add (OLA) inverse FFT with synthesis window normalization.
- **Execution Performance:** $< 2\text{ms}$ execution latency on Apple Silicon for 10-second audio clips with zero memory allocations during inference.


