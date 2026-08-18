# VoiceTyper Manual Test Scenarios

This document contains a series of scripts and instructions to manually verify the functionality of VoiceTyper.

## Setup
Ensure VoiceTyper is running via your terminal (`.build/release/VoiceTyper` or `.build/debug/VoiceTyper`) and the menu bar icon (🎙️) is visible.
Click into any text editor (even a blank document) to begin testing.

---

## Scenario 1: Basic Transcription
**Goal:** Verify that holding the hotkey records audio and pastes text correctly.
**Action:** 
1. Hold `Right Option`. The icon should turn to 🔴.
2. Clearly read the following sentence:
> "The quick brown fox jumps over the lazy dog."
3. Release `Right Option`. The icon should turn to ⏳.
4. Wait for the text to be pasted. 
**Expected result:** The transcribed text appears with reasonable accuracy and punctuation.

## Scenario 2: Grace Period (Pausing mid-sentence)
**Goal:** Verify that the 400ms grace period allows the user to take a quick breath without ending the transcription.
**Action:**
1. Hold `Right Option` and speak:
> "This is the first half of my sentence,"
2. **Release** `Right Option` very briefly (under half a second), and immediately **Hold** it down again.
3. Speak the rest:
> "and this is the second half."
4. Release `Right Option` for good.
**Expected result:** The entire phrase is transcribed as a single, combined output, rather than two separate chunks.

## Scenario 3: Double-Tap Abort
**Goal:** Verify that rapidly double-tapping the hotkey discards the recording completely.
**Action:**
1. Hold `Right Option` and start speaking:
> "I am going to change my mind and abort this recorded message."
2. Before you finish, release `Right Option` and immediately press it again quickly (double-tap).
**Expected result:** The icon should revert to 🎙️, no transcription processes (no ⏳ icon), and no text is pasted. Check terminal logs for `🚫 Aborted. Audio discarded.`

## Scenario 4: Silence Rejection
**Goal:** Verify that accidental hotkey presses without speaking do not type random artifacts.
**Action:**
1. Hold `Right Option` for about 3 seconds in complete silence.
2. Release `Right Option`.
**Expected result:** The app processes the silence but should not paste any text like `[BLANK_AUDIO]` or `(silence)`. The terminal log should show `🔕 Silence detected, nothing to type.`

## Scenario 5: Clipboard Preservation
**Goal:** VoiceTyper simulates Command+V to paste text. This test ensures your original clipboard contents aren't permanently overwritten.
**Action:**
1. Highlight this very word: **PINEAPPLE**, and press `Command + C` to copy it.
2. Hold `Right Option` and say:
> "I am speaking some text right now."
3. Release `Right Option` and wait for the transcription to paste.
4. On your keyboard, press `Command + V` manually.
**Expected result:** VoiceTyper pastes its transcription successfully, but when you manually press paste, the word **PINEAPPLE** should appear.

## Scenario 6: Speed and Punctuation Handling
**Goal:** Verify the model's ability to interpret speed and natural punctuation.
**Action:**
1. Hold `Right Option` and read the following in a fast but conversational tone:
> "Wait, what? Are you seriously telling me that we need to rewrite this entire module by tomorrow morning? That's impossible!"
2. Release `Right Option`.
**Expected result:** Transcription accurately places commas, question marks, and exclamation points based on the inflection of your voice.

## Scenario 7: Force Stop Processing (`Ctrl + C`)
**Goal:** Verify that a user can explicitly cancel dictation during the `processing...` phase.
**Action:**
1. Hold `Right Option` and speak a very long paragraph to ensure the transcription takes a few seconds.
2. Release `Right Option`. The `processing...` animation will begin typing.
3. Immediately press `Control + C` on your keyboard.
**Expected result:** The `processing...` animation instantly stops and deletes itself. The terminal logs `🚫 Aborted. Dictation discarded.`, and no final transcribed text is injected.

## Scenario 8: Dynamic Vocabulary Biasing & Prompt Leakage Prevention
**Goal:** Verify that domain-specific technical terms (e.g. OpenSCAD, minkowski, Bouwplank, AggregateRoot) are recognized accurately without hallucinations.
**Action:**
1. Hold `Right Option` and speak:
> "We should test the minkowski operator in OpenSCAD for the Bouwplank layout."
2. Release `Right Option`.
**Expected result:** 
- The technical terms `minkowski`, `OpenSCAD`, and `Bouwplank` appear with exact casing and spelling rather than phonetic corruptions (e.g. not *"men cow ski"* or *"open scab"*).
- When holding the hotkey in complete silence, no injected prompt keywords are leaked or pasted into the active text field.

## Scenario 9: Hands-Free Voice Conversation Note Archiving (`Shift + Right Option`)
**Goal:** Verify that tapping `Shift + Right Option` once starts hands-free recording, floating indicator displays minimal pill (`🟣 01 │ 00:00`), and a second tap saves the memo without typing at the cursor.
**Action:**
1. Focus any text field with existing text.
2. Tap `Shift + Right Option` once and release your fingers.
3. Observe the floating indicator at the bottom center: it appears as a sleek glassmorphic pill with breathing purple dot `🟣`, lap badge `01`, and live ticking timer `00:01`, `00:02`...
4. Speak naturally:
> "Decision: We are standardizing all civil CAD diagrams on OpenSCAD and Three.js runtime."
5. Tap `Shift + Right Option` a second time (or click the floating pill).
**Expected result:**
- The active cursor is **not** typed into (no clipboard injection).
- Raw audio is saved to `~/.voicetyper/conversation/<YYYY-MM-DD>/audio/conversation_<timestamp>_<id>_part1.wav`.
- Transcribed text is saved to `~/.voicetyper/conversation/<YYYY-MM-DD>/text/conversation_<timestamp>_<id>_part1.txt`.
- History window logs the entry with `🧠 [Part 1]`.

## Scenario 10: Rolling 5-Minute Lap Rollover
**Goal:** Verify that long-form conversations automatically segment every 5 minutes (`300s`) into consecutive parts without dropping audio frames.
**Action:**
1. Start hands-free capture via `Shift + Right Option`.
2. Allow recording to run past the 5-minute mark (or simulate in unit test `ConversationLapManagerTests`).
**Expected result:**
- At 05:00, the floating pill flips to `🟣 02 │ 00:00`.
- Part 1 (`_part1.wav`) is written to disk and queued for background transcription.
- Part 2 continues capturing audio in a fresh buffer without interrupting the microphone.

## Scenario 11: 1-Minute Silence Auto-Stop Safeguard
**Goal:** Verify that if the user walks away without stopping, continuous silence for 60 seconds automatically concludes the session.
**Action:**
1. Start hands-free capture via `Shift + Right Option`.
2. Speak a quick sentence, then remain completely silent for 65 seconds.
**Expected result:**
- At 60 seconds of continuous silence, VoiceTyper triggers `onSilenceTimeout`.
- The session automatically closes, writes the audio and text to disk, and hides the floating pill.
- Prevents overnight recording of empty rooms.

## Scenario 12: Native Audio DSP Noise Removal
**Goal:** Verify that background electrical hum (<80Hz) and ambient fan noise are filtered before Whisper inference.
**Action:**
1. Run in an environment with laptop cooling fan or background AC hum.
2. Hold `Right Option` and dictate a short sentence.
**Expected result:**
- Audio is processed through the 4th-order 80Hz Butterworth filter and Accelerate vDSP spectral subtraction in $<2\text{ms}$.
- Transcription does not hallucinate pause tokens (e.g. `[Music]`, `Thank you`).
- Unit test `AudioDSPTests` confirms $>15\text{dB}$ attenuation on 60Hz hum.

## Scenario 13: Swift Symbol, Import & Memory Exclusivity Gate (`make test`)
**Goal:** Verify that static AST syntax, imports, and buffer memory exclusivity are verified before any commit is pushed.
**Action:**
1. Run `make test` from repository root.
**Expected result:**
- `tests/verify_symbols.sh` runs as Step 1, validating all framework imports (`Cocoa`, `Foundation`), property deduplication in `App.swift`, and buffer pointer exclusivity (`realPtr[k]` vs `real[k]`).
- Full unit test suite and sandbox installation test suite pass with exit code `0`.
