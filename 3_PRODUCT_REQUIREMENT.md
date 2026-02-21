# 3. Product Requirements Document: VoiceTyper

**Product Vision**
VoiceTyper is a privacy-first, zero-latency macOS dictation client that operates entirely on-device. It is built to seamlessly translate rapid thought into typed text without depending on internet connectivity, third-party APIs, or subscription costs.

**Target Audience**
Power users, rapid typers, developers, and writers seeking an offline macOS speech-to-text solution that works anywhere they can type.

---

## 1. Core User Workflows

### 1.1 Triggering Dictation (Hold-to-Talk)
- Users interact solely through a global hardware hotkey (`Right Shift`).
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
- **Trigger:** Rapidly double-tapping the `Right Shift` hotkey during dictation.
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
