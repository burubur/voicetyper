# Product Requirements Document: VoiceTyper

**Objective:**
Deliver a privacy-first, zero-latency macOS dictation application that operates entirely offline. The application must bridge the gap between rapid thought and text insertion by eliminating relying on third-party cloud APIs or complex graphical interfaces.

**Target Audience:**
Developers, writers, and power users who require fast, private, and highly accessible voice-to-text dictation across any desktop application constraint.

## Core Capabilities
1. **Universal Dictation (Hold-To-Talk):**
   - The system triggers explicitly via a persistent global hotkey (`Right Shift`).
   - Transcription only occurs while the key is depressed, eliminating accidental listening.
2. **Instant Delivery:**
   - The transcribed text is automatically injected into whichever application/text-field the user currently has focused.
3. **Absolute Privacy (Offline-First):**
   - 100% of speech recognition happens locally on the machine.
   - Zero internet connectivity required. No API keys, zero data collection.
4. **Adaptive UX Constraints:**
   - **Grace Period:** Allow brief mid-sentence pauses (up to 400ms) without fragmenting the final sentence.
   - **Silence Rejection:** Drop requests natively if the user holds the key but no audible speech is detected.
   - **Abort Sequence:** Double-tapping the hotkey mid-dictation silently cancels the entire operation.
5. **Real-time Visual Feedback:**
   - **Status Indicators:** Menu bar icon states (🎙️ Idle, 🔴 Recording, ⏳ Processing).
   - **Floating Mic:** An elegant, animated floating microphone overlay positioned at the bottom of the active screen during recording.
   - **Progress Injection:** An animated `processing...` placeholder directly within the target text field while the AI decodes the audio.

## Out of Scope
- GUI settings panels.
- Streaming/live transcription (batch prediction only).
- Grammar correction using external LLMs.
