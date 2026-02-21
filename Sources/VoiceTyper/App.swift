import AVFoundation
import Cocoa

// MARK: - App

/// Main orchestrator that wires together audio recording, transcription,
/// text injection, and keyboard listening into the menu bar app.
@MainActor
final class App: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let audioRecorder = AudioRecorder()
    private let textInjector = TextInjector()
    private let keyboardListener = KeyboardListener()
    private var transcriber: Transcriber?

    /// Tracks whether an abort was requested to cancel in-flight transcription.
    private var abortRequested = false

    /// Queues transcriptions sequentially to prevent SwiftWhisper `instanceBusy` errors.
    private var transcriptionTask: Task<Void, Never>?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()
        setupMenuBar()
        loadModel()
        keyboardListener.delegate = self

        FloatingRecordingIndicator.shared.onAbort = { [weak self] in
            self?.keyboardListener.forceAbort()
        }

        keyboardListener.start()
    }

    // MARK: - Setup

    private func requestPermissions() {
        // Microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("✅ Microphone access granted.")
            } else {
                print("❌ Microphone access denied. VoiceTyper requires microphone access.")
            }
        }

        // Accessibility permission (needed for CGEvent tap + keyboard simulation)
        // Hardcoding the string equivalent of `kAXTrustedCheckOptionPrompt` avoids concurrency warnings
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            print("✅ Accessibility access granted.")
        } else {
            print("⚠️  Accessibility access not granted. Please allow in:")
            print("   System Settings > Privacy & Security > Accessibility")
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(symbol: "mic")

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Quit VoiceTyper", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func loadModel() {
        guard let modelURL = WhisperTranscriber.resolveModelURL() else {
            print("❌ Cannot start without a whisper model. Exiting.")
            NSApplication.shared.terminate(self)
            return
        }

        do {
            transcriber = try WhisperTranscriber(modelURL: modelURL)
            print("✅ Whisper model loaded from: \(modelURL.path)")
        } catch {
            print("❌ Failed to load whisper model: \(error)")
            NSApplication.shared.terminate(self)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }

    // MARK: - Transcription Pipeline

    private func processRecording() {
        let audioFrames = audioRecorder.stopRecording()

        // Reject too-short recordings (~< 0.3 seconds)
        guard audioFrames.count >= AudioRecorder.minimumFrameCount else {
            print("🔕 Recording too short, ignoring.")
            updateIcon(symbol: "mic")
            return
        }

        updateIcon(symbol: "waveform.circle")
        print("🧠 Transcribing \(audioFrames.count) frames locally...")

        // Run transcription; task inherits MainActor but await will yield
        let abortFlag = abortRequested
        let previousTask = self.transcriptionTask

        self.transcriptionTask = Task { [weak self] in
            // Wait for any existing transcription to finish first
            _ = await previousTask?.result

            guard let self = self, let transcriber = self.transcriber else { return }

            // Check abort before starting
            guard !abortFlag, !self.abortRequested else {
                print("🚫 Transcription cancelled (abort requested).")
                self.updateIcon(symbol: "mic")
                return
            }

            self.textInjector.startProcessingAnimation()

            do {
                let text = try await transcriber.transcribe(audioFrames: audioFrames)

                self.textInjector.stopProcessingAnimation()

                // Check abort after transcription completes
                guard !self.abortRequested else {
                    print("🚫 Transcription result discarded (abort requested).")
                    self.updateIcon(symbol: "mic")
                    return
                }

                if text.isEmpty {
                    print("🔕 Silence detected, nothing to type.")
                    self.updateIcon(symbol: "mic")
                    return
                }

                print("✅ Transcribed: \(text)")
                // Append trailing space so consecutive dictations don't merge
                self.textInjector.injectText(text + " ")
                self.updateIcon(symbol: "mic")

            } catch {
                self.textInjector.stopProcessingAnimation()
                print("❌ Transcription error: \(error)")
                self.updateIcon(symbol: "mic")
            }
        }
    }

    // MARK: - Helpers

    private func updateIcon(symbol: String) {
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true  // Adapts to light/dark mode
            self.statusItem.button?.image = image
            self.statusItem.button?.title = ""
        }
    }
}

// MARK: - KeyboardListenerDelegate

extension App: KeyboardListenerDelegate {
    func keyboardListenerDidStartRecording() {
        abortRequested = false
        updateIcon(symbol: "mic.fill")
        FloatingRecordingIndicator.shared.show()

        do {
            try audioRecorder.startRecording()
            print("🎙️ Recording... (speak now)")
        } catch {
            print("❌ Failed to start recording: \(error)")
            updateIcon(symbol: "mic")
        }
    }

    func keyboardListenerDidStopRecording() {
        print("⏹️  Recording stopped. Processing...")
        FloatingRecordingIndicator.shared.hide()
        processRecording()
    }

    func keyboardListenerDidAbort() {
        abortRequested = true
        _ = audioRecorder.stopRecording()  // Discard audio
        textInjector.stopProcessingAnimation()  // Instantly clear any ongoing injection animation
        FloatingRecordingIndicator.shared.hide()
        updateIcon(symbol: "mic")
        print("🚫 Aborted. Dictation discarded.")
    }
}
