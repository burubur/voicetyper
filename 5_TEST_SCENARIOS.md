# VoiceTyper Manual Test Scenarios

This document contains a series of scripts and instructions to manually verify the functionality of VoiceTyper.

## Setup
Ensure VoiceTyper is running via your terminal (`.build/release/VoiceTyper` or `.build/debug/VoiceTyper`) and the menu bar icon (🎙️) is visible.
Click into any text editor (even a blank document) to begin testing.

---

## Scenario 1: Basic Transcription
**Goal:** Verify that holding the hotkey records audio and pastes text correctly.
**Action:** 
1. Hold `Right Shift`. The icon should turn to 🔴.
2. Clearly read the following sentence:
> "The quick brown fox jumps over the lazy dog."
3. Release `Right Shift`. The icon should turn to ⏳.
4. Wait for the text to be pasted. 
**Expected result:** The transcribed text appears with reasonable accuracy and punctuation.

## Scenario 2: Grace Period (Pausing mid-sentence)
**Goal:** Verify that the 400ms grace period allows the user to take a quick breath without ending the transcription.
**Action:**
1. Hold `Right Shift` and speak:
> "This is the first half of my sentence,"
2. **Release** `Right Shift` very briefly (under half a second), and immediately **Hold** it down again.
3. Speak the rest:
> "and this is the second half."
4. Release `Right Shift` for good.
**Expected result:** The entire phrase is transcribed as a single, combined output, rather than two separate chunks.

## Scenario 3: Double-Tap Abort
**Goal:** Verify that rapidly double-tapping the hotkey discards the recording completely.
**Action:**
1. Hold `Right Shift` and start speaking:
> "I am going to change my mind and abort this recorded message."
2. Before you finish, release `Right Shift` and immediately press it again quickly (double-tap).
**Expected result:** The icon should revert to 🎙️, no transcription processes (no ⏳ icon), and no text is pasted. Check terminal logs for `🚫 Aborted. Audio discarded.`

## Scenario 4: Silence Rejection
**Goal:** Verify that accidental hotkey presses without speaking do not type random artifacts.
**Action:**
1. Hold `Right Shift` for about 3 seconds in complete silence.
2. Release `Right Shift`.
**Expected result:** The app processes the silence but should not paste any text like `[BLANK_AUDIO]` or `(silence)`. The terminal log should show `🔕 Silence detected, nothing to type.`

## Scenario 5: Clipboard Preservation
**Goal:** VoiceTyper simulates Command+V to paste text. This test ensures your original clipboard contents aren't permanently overwritten.
**Action:**
1. Highlight this very word: **PINEAPPLE**, and press `Command + C` to copy it.
2. Hold `Right Shift` and say:
> "I am speaking some text right now."
3. Release `Right Shift` and wait for the transcription to paste.
4. On your keyboard, press `Command + V` manually.
**Expected result:** VoiceTyper pastes its transcription successfully, but when you manually press paste, the word **PINEAPPLE** should appear.

## Scenario 6: Speed and Punctuation Handling
**Goal:** Verify the model's ability to interpret speed and natural punctuation.
**Action:**
1. Hold `Right Shift` and read the following in a fast but conversational tone:
> "Wait, what? Are you seriously telling me that we need to rewrite this entire module by tomorrow morning? That's impossible!"
2. Release `Right Shift`.
**Expected result:** Transcription accurately places commas, question marks, and exclamation points based on the inflection of your voice.

## Scenario 7: Force Stop Processing (`Ctrl + C`)
**Goal:** Verify that a user can explicitly cancel dictation during the `processing...` phase.
**Action:**
1. Hold `Right Shift` and speak a very long paragraph to ensure the transcription takes a few seconds.
2. Release `Right Shift`. The `processing...` animation will begin typing.
3. Immediately press `Control + C` on your keyboard.
**Expected result:** The `processing...` animation instantly stops and deletes itself. The terminal logs `🚫 Aborted. Dictation discarded.`, and no final transcribed text is injected.
