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

    /// Models currently being downloaded in the background.
    private var downloadingModels: Set<String> = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()
        setupMenuBar()
        setupHistoryWindow()
        
        keyboardListener.delegate = self
        FloatingRecordingIndicator.shared.onAbort = { [weak self] in
            self?.keyboardListener.forceAbort()
        }
        
        loadModel()
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

        var headerTitle = "VoiceTyper (\(modelTitle))"
        if !downloadingModels.isEmpty {
            headerTitle += " — Downloading model..."
        }

        let titleItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show VoiceTyper", action: #selector(showHistoryWindow), keyEquivalent: ""))

        // Model selection submenu
        let modelSubmenu = NSMenu(title: "Select Model")
        for option in WhisperTranscriber.availableModels {
            let isCurrent = option.filename.lowercased() == currentModel.lowercased()
            let isDownloaded = WhisperTranscriber.isModelDownloaded(filename: option.filename)
            let isDownloading = downloadingModels.contains(option.filename)

            let statusSuffix: String
            if isDownloading {
                statusSuffix = " (Downloading...)"
            } else if isDownloaded {
                statusSuffix = ""
            } else {
                statusSuffix = " (Download needed)"
            }
            let itemTitle = "\(option.displayName) — \(option.sizeDescription)\(statusSuffix)"

            let item = NSMenuItem(title: itemTitle, action: #selector(modelSubmenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.filename
            item.state = isCurrent ? .on : .off
            if isDownloading {
                item.isEnabled = false
            }
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
            print("🎙️ Right Shift and hold to record.")
        }

        historyWindowController.onSettingsPressed = { [weak self] view in
            guard let self else { return }
            self.showModelMenu(anchoredAt: view)
        }

        historyWindowController.showWindow(nil)
    }

    func showModelMenu(anchoredAt view: NSView) {
        let menu = NSMenu()
        let currentModel = WhisperTranscriber.configuredModelFilename

        let headerItem = NSMenuItem(title: "Select Speech Model", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        for option in WhisperTranscriber.availableModels {
            let isCurrent = option.filename.lowercased() == currentModel.lowercased()
            let isDownloaded = WhisperTranscriber.isModelDownloaded(filename: option.filename)
            let isDownloading = downloadingModels.contains(option.filename)

            let statusSuffix: String
            if isDownloading {
                statusSuffix = " (Downloading...)"
            } else if isDownloaded {
                statusSuffix = ""
            } else {
                statusSuffix = " (Download needed)"
            }
            let itemTitle = "\(option.displayName) — \(option.sizeDescription)\(statusSuffix)"

            let item = NSMenuItem(title: itemTitle, action: #selector(modelSubmenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.filename
            item.state = isCurrent ? .on : .off
            if isDownloading {
                item.isEnabled = false
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let openFolderItem = NSMenuItem(title: "Open Model Directory (~/.voicetyper)", action: #selector(openModelFolder), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        let location = NSPoint(x: 0, y: view.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: view)
    }

    @objc private func openModelFolder() {
        let dir = WhisperTranscriber.defaultModelDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func loadModel() {
        if let modelURL = WhisperTranscriber.resolveModelURL().1 {
            finishLoadingModel(url: modelURL)
        } else {
            historyWindowController.showWindow(nil)
            historyWindowController.startOnboardingDownload { [weak self] success in
                Task { @MainActor in
                    if success, let url = WhisperTranscriber.resolveModelURL().1 {
                        self?.finishLoadingModel(url: url)
                    } else {
                        self?.keyboardListener.start()
                        print("⚠️ No model loaded. App is running but dictation is disabled.")
                    }
                }
            }
        }
    }
    
    private func finishLoadingModel(url: URL) {
        do {
            if !url.path.contains("parakeet") {
                transcriber = try WhisperTranscriber(modelURL: url)
                print("✅ Whisper model loaded from: \(url.path)")
            } else {
                transcriber = try ParakeetTranscriber(modelDir: url)
                print("✅ Parakeet model loaded from: \(url.path)")
            }
            keyboardListener.start()
        } catch {
            print("❌ Failed to load whisper model: \(error)")
            NSApplication.shared.terminate(self)
        }
    }

    func switchModel(filename: String) {
        if downloadingModels.contains(filename) {
            let alert = NSAlert()
            alert.messageText = "Download in Progress"
            alert.informativeText = "The model '\(filename)' is currently downloading in the background."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let isDownloaded = WhisperTranscriber.isModelDownloaded(filename: filename)

        if !isDownloaded {
            let alert = NSAlert()
            alert.messageText = "Download Speech Model"
            alert.informativeText = "The model '\(filename)' is not downloaded yet at ~/.voicetyper/\n\nWould you like to download it now in the background?"
            alert.addButton(withTitle: "Download in Background")
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
            } else {
                let parakeetDir = WhisperTranscriber.defaultModelDirectory.appendingPathComponent(
                    filename == "parakeet-unified-0.6b"
                        ? "sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming"
                        : "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"
                )
                transcriber = try ParakeetTranscriber(modelDir: parakeetDir)
            }
            UserDefaults.standard.set(filename, forKey: "WHISPER_MODEL")
            rebuildMenuBar()
            print("✅ Switched model to: \(filename)")
        } catch {
            print("❌ Failed to switch model to \(filename): \(error)")
        }
    }

    private func downloadAndLoadModel(filename: String) {
        guard !downloadingModels.contains(filename) else { return }

        downloadingModels.insert(filename)
        rebuildMenuBar()
        historyWindowController.setDownloadingState(modelName: filename)

        print("📥 Starting background download for model \(filename)...")

        let currentDir = FileManager.default.currentDirectoryPath

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")

            var scriptPath = URL(fileURLWithPath: currentDir)
                .appendingPathComponent("download-models.sh").path

            if !FileManager.default.fileExists(atPath: scriptPath) {
                if let bundleScript = Bundle.main.path(forResource: "download-models", ofType: "sh") {
                    scriptPath = bundleScript
                }
            }

            process.arguments = [scriptPath, filename]

            var success = false
            do {
                try process.run()
                process.waitUntilExit()
                success = (process.terminationStatus == 0)
            } catch {
                print("❌ Error running download script: \(error)")
                success = false
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.downloadingModels.remove(filename)
                self.rebuildMenuBar()
                
                if self.downloadingModels.isEmpty {
                    self.historyWindowController.setDownloadingState(modelName: nil as String?)
                } else {
                    self.historyWindowController.setDownloadingState(modelName: self.downloadingModels.first)
                }

                if success {
                    print("✅ Download completed for \(filename)")
                    self.switchModel(filename: filename)

                    let alert = NSAlert()
                    alert.messageText = "Download Complete"
                    alert.informativeText = "The model '\(filename)' was successfully downloaded and activated."
                    alert.alertStyle = .informational
                    alert.runModal()
                } else {
                    print("❌ Failed to download model \(filename)")
                    let alert = NSAlert()
                    alert.messageText = "Download Failed"
                    alert.informativeText = "Failed to download model '\(filename)'. Please check your network connection and try again."
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
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

        // Calculate peak amplitude to detect absolute silence (e.g. mic permission denied)
        var maxAmplitude: Float = 0
        for sample in audioFrames {
            let absSample = abs(sample)
            if absSample > maxAmplitude {
                maxAmplitude = absSample
            }
        }
        
        // If amplitude is basically zero, skip transcription to prevent Whisper hallucinations
        guard maxAmplitude > 0.005 else {
            print("🔕 Audio is silent (max amp: \(maxAmplitude)). Skipping to prevent hallucination.")
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

            await self.textInjector.startProcessingAnimation()

            do {
                let text = try await transcriber.transcribe(audioFrames: audioFrames)

                await self.textInjector.stopProcessingAnimation()

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
                await self.textInjector.stopProcessingAnimation()
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
        guard transcriber != nil else {
            keyboardListener.forceAbort()
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Speech Model Required"
            alert.informativeText = "You need to download a speech model before you can start dictating. Please click the Settings gear icon in the history window to download a model."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
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
        
        Task { @MainActor in
            await textInjector.stopProcessingAnimation()  // Instantly clear any ongoing injection animation
            historyWindowController.setRecording(false)
            FloatingRecordingIndicator.shared.hide()
            updateIcon(symbol: "mic")
            print("🚫 Aborted. Dictation discarded.")
        }
    }
}
