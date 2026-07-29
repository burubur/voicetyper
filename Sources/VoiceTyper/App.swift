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
    private let historyWindowController = TranscriptionHistoryWindowController()
    private var transcriber: Transcriber?

    /// Tracks whether an abort was requested to cancel in-flight transcription.
    private var abortRequested = false

    /// Queues transcriptions sequentially to prevent SwiftWhisper `instanceBusy` errors.
    private var transcriptionTask: Task<Void, Never>?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()
        setupMenuBar()
        setupHistoryWindow()
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
        rebuildMenuBar()
    }

    private func rebuildMenuBar() {
        let menu = NSMenu()
        let currentModel = WhisperTranscriber.configuredModelFilename
        let currentOption = WhisperTranscriber.availableModels.first { $0.filename.lowercased() == currentModel.lowercased() }
        let modelTitle = currentOption?.displayName ?? currentModel

        let titleItem = NSMenuItem(title: "VoiceTyper (\(modelTitle))", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show VoiceTyper", action: #selector(showHistoryWindow), keyEquivalent: ""))

        // Model selection submenu
        let modelSubmenu = NSMenu(title: "Select Model")
        for option in WhisperTranscriber.availableModels {
            let isCurrent = option.filename.lowercased() == currentModel.lowercased()
            let isDownloaded = WhisperTranscriber.isModelDownloaded(filename: option.filename)
            let statusSuffix = isDownloaded ? "" : " (Download needed)"
            let itemTitle = "\(option.displayName) — \(option.sizeDescription)\(statusSuffix)"

            let item = NSMenuItem(title: itemTitle, action: #selector(modelSubmenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.filename
            item.state = isCurrent ? .on : .off
            modelSubmenu.addItem(item)
        }

        let modelSubmenuItem = NSMenuItem(title: "Select Whisper Model", action: nil, keyEquivalent: "")
        modelSubmenuItem.submenu = modelSubmenu
        menu.addItem(modelSubmenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VoiceTyper", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func modelSubmenuItemClicked(_ sender: NSMenuItem) {
        guard let filename = sender.representedObject as? String else { return }
        switchModel(filename: filename)
    }

    private func setupHistoryWindow() {
        historyWindowController.onMicPressed = { [weak self] in
            guard let self else { return }
            self.showHistoryWindow()
            print("🎙️ Hold Right Shift to record.")
        }

        historyWindowController.onSettingsPressed = { [weak self] in
            guard let self else { return }
            self.showHistoryWindow()
        }

        historyWindowController.onModelSelected = { [weak self] filename in
            guard let self else { return }
            self.switchModel(filename: filename)
        }

        historyWindowController.setSelectedModel(WhisperTranscriber.configuredModelFilename)
        historyWindowController.showWindow(nil)
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

    func switchModel(filename: String) {
        let isDownloaded = WhisperTranscriber.isModelDownloaded(filename: filename)

        if !isDownloaded {
            let alert = NSAlert()
            alert.messageText = "Download Speech Model"
            alert.informativeText = "The model '\(filename)' is not downloaded yet at ~/.voicetyper/\n\nWould you like to download it now?"
            alert.addButton(withTitle: "Download Now")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .informational

            if alert.runModal() == .alertFirstButtonReturn {
                downloadAndLoadModel(filename: filename)
            }
            return
        }

        let modelFilename = filename.contains("parakeet") ? filename : (filename.hasSuffix(".bin") ? filename : "\(filename).bin")
        let modelURL = WhisperTranscriber.defaultModelDirectory.appendingPathComponent(modelFilename)

        do {
            if !filename.contains("parakeet") {
                transcriber = try WhisperTranscriber(modelURL: modelURL)
            }
            UserDefaults.standard.set(filename, forKey: "WHISPER_MODEL")
            historyWindowController.setSelectedModel(filename)
            rebuildMenuBar()
            print("✅ Switched model to: \(filename)")
        } catch {
            print("❌ Failed to switch model to \(filename): \(error)")
        }
    }

    private func downloadAndLoadModel(filename: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        let scriptPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("download-models.sh").path

        process.arguments = [scriptPath, filename]

        print("📥 Downloading model \(filename)...")
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                switchModel(filename: filename)
            } else {
                print("❌ Failed to download model \(filename)")
            }
        } catch {
            print("❌ Error running download script: \(error)")
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }

    @objc private func showHistoryWindow() {
        historyWindowController.showWindow(nil)
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
                self.historyWindowController.appendTranscription(text)
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
        historyWindowController.setRecording(true)
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
        historyWindowController.setRecording(false)
        FloatingRecordingIndicator.shared.hide()
        processRecording()
    }

    func keyboardListenerDidAbort() {
        abortRequested = true
        _ = audioRecorder.stopRecording()  // Discard audio
        textInjector.stopProcessingAnimation()  // Instantly clear any ongoing injection animation
        historyWindowController.setRecording(false)
        FloatingRecordingIndicator.shared.hide()
        updateIcon(symbol: "mic")
        print("🚫 Aborted. Dictation discarded.")
    }
}
