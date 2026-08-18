import AVFoundation
import Cocoa

// MARK: - App

/// Main orchestrator that wires together audio recording, transcription,
/// text injection, and keyboard listening into the menu bar app.
public enum ActiveMode: String, CaseIterable, Sendable {
    case smartDual = "smart_dual"
    case directOnly = "direct_only"
    case conversationOnly = "conversation_only"

    var displayName: String {
        switch self {
        case .smartDual:
            return "Smart Dual (⌥ Direct / ⇧⌥ Memo)"
        case .directOnly:
            return "Direct Dictation Only (⌥)"
        case .conversationOnly:
            return "Hands-Free Memo Only (⇧⌥)"
        }
    }
}

@MainActor
final class App: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let audioRecorder = AudioRecorder()
    private let textInjector = TextInjector()
    private let keyboardListener = KeyboardListener()
    private let conversationStorage = VoiceConversationStorage()
    private let lapManager = ConversationLapManager(lapDuration: 300.0, silenceTimeout: 60.0)
    private var lapTimer: Timer?
    private let historyWindowController = TranscriptionHistoryWindowController()
    private var transcriber: Transcriber?
    private var activeVocabulary: [String] = []

    /// Tracks whether an abort was requested to cancel in-flight transcription.
    private var abortRequested = false

    /// Queues transcriptions sequentially to prevent SwiftWhisper `instanceBusy` errors.
    private var transcriptionTask: Task<Void, Never>?

    /// Models currently being downloaded in the background.
    private var downloadingModels: Set<String> = []

    private var activeMode: ActiveMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "voicetyper_active_mode") ?? ActiveMode.smartDual.rawValue
            return ActiveMode(rawValue: raw) ?? .smartDual
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "voicetyper_active_mode")
            rebuildMenuBar()
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
        requestPermissions()
        setupMenuBar()
        setupHistoryWindow()
        
        keyboardListener.delegate = self
        FloatingRecordingIndicator.shared.onAbort = { [weak self] in
            self?.keyboardListener.forceAbort()
        }

        audioRecorder.onAudioLevel = { level in
            Task { @MainActor in
                FloatingRecordingIndicator.shared.updateAudioLevel(level)
            }
        }

        lapManager.onLapRollover = { [weak self] completedLap, lapFrames in
            guard let self else { return }
            Task { @MainActor in
                print("🔄 Lap \(completedLap) completed (5 mins). Archiving Part \(completedLap)...")
                FloatingRecordingIndicator.shared.updateLap(self.lapManager.currentLap)
                self.processLapRecording(lap: completedLap, audioFrames: lapFrames)
            }
        }

        lapManager.onSilenceTimeout = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                print("⏱️ 1-Minute silence timeout detected. Auto-stopping conversation capture...")
                self.keyboardListenerDidStopRecording(mode: .memoryVault)
            }
        }
        
        loadModel()

        // Asynchronously load dynamic ubiquitous vocabulary from memory graph/cache
        Task { [weak self] in
            guard let self = self else { return }
            let vocab = await VocabularyManager.loadActiveVocabulary()
            self.activeVocabulary = vocab
            if let whisper = self.transcriber as? WhisperTranscriber {
                whisper.setVocabulary(terms: vocab)
            } else if let parakeet = self.transcriber as? ParakeetTranscriber {
                parakeet.setVocabulary(terms: vocab)
            }
            print("🧠 Loaded \(vocab.count) domain vocabulary terms for dynamic biasing.")
        }
    }

    // MARK: - Setup

    private func enforceSingleInstance() {
        let pidFile = UpgradeManager.voicetyperHome.appendingPathComponent("voicetyper.pid")
        try? FileManager.default.createDirectory(at: UpgradeManager.voicetyperHome, withIntermediateDirectories: true)
        
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let oldPIDString = try? String(contentsOf: pidFile, encoding: .utf8),
           let oldPID = Int32(oldPIDString.trimmingCharacters(in: .whitespacesAndNewlines)),
           oldPID != currentPID {
            // Terminate previous duplicate process
            kill(oldPID, SIGTERM)
            print("🛑 Terminated previous duplicate VoiceTyper instance (PID: \(oldPID))")
        }
        
        try? "\(currentPID)".write(to: pidFile, atomically: true, encoding: .utf8)
    }

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
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            print("✅ Accessibility access granted.")
        } else {
            print("⚠️  Accessibility access not granted. Please allow in:")
            print("   System Settings > Privacy & Security > Accessibility")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(symbol: "mic")
        rebuildMenuBar()
    }

    private func rebuildMenuBar() {
        let menu = buildNativeMenu()
        statusItem.menu = menu
    }

    private func buildNativeMenu() -> NSMenu {
        let menu = NSMenu()
        let currentModel = WhisperTranscriber.configuredModelFilename

        // Header: Version & Active Model
        let titleItem = NSMenuItem(title: "VoiceTyper v\(UpgradeManager.currentVersion)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Section 1: Top Actions (History & Vault)
        let historyItem = NSMenuItem(title: "Show VoiceTyper", action: #selector(showHistoryWindow), keyEquivalent: "h")
        historyItem.keyEquivalentModifierMask = [.command]
        historyItem.target = self
        menu.addItem(historyItem)

        let vaultItem = NSMenuItem(title: "Open Daily Vault Folder", action: #selector(openConversationsFolder), keyEquivalent: "")
        vaultItem.target = self
        menu.addItem(vaultItem)

        menu.addItem(NSMenuItem.separator())

        // Section 2: Mode Selection
        let modeHeader = NSMenuItem(title: "Mode:", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)

        for mode in ActiveMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(modeMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.indentationLevel = 1
            item.representedObject = mode.rawValue
            item.state = (mode == activeMode) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Section 3: Select Whisper Model Flyout Submenu & System Actions
        let modelSubmenu = NSMenu(title: "Select Whisper Model")
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
            item.indentationLevel = 1
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

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(title: "Quit VoiceTyper", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "VoiceTyper v\(UpgradeManager.currentVersion)"
        alert.informativeText = "To update VoiceTyper to the latest version, run:\n\nvoicetyper upgrade\n\nin your terminal."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "View Releases on GitHub")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/burubur/voicetyper/releases") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func openConversationsFolder() {
        let dir = conversationStorage.dayDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func modeMenuItemClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ActiveMode(rawValue: raw) else { return }
        self.activeMode = mode
    }

    @objc private func modelSubmenuItemClicked(_ sender: NSMenuItem) {
        guard let filename = sender.representedObject as? String else { return }
        switchModel(filename: filename)
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
                transcriber = try WhisperTranscriber(modelURL: url, vocabulary: activeVocabulary)
                print("✅ Whisper model loaded from: \(url.path)")
            } else {
                transcriber = try ParakeetTranscriber(modelDir: url, vocabulary: activeVocabulary)
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
                transcriber = try WhisperTranscriber(modelURL: modelURL, vocabulary: activeVocabulary)
            } else {
                let parakeetDir = WhisperTranscriber.defaultModelDirectory.appendingPathComponent(
                    filename == "parakeet-unified-0.6b"
                        ? "sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming"
                        : "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"
                )
                transcriber = try ParakeetTranscriber(modelDir: parakeetDir, vocabulary: activeVocabulary)
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

    private func processRecording(mode: DictationMode = .standard, lap: Int? = nil) {
        let audioFrames = audioRecorder.stopRecording()

        // Reject too-short recordings (~< 0.4 seconds)
        guard audioFrames.count >= AudioRecorder.minimumFrameCount else {
            print("🔕 Recording too short (\(audioFrames.count) frames), ignoring.")
            updateIcon(symbol: "mic")
            return
        }

        // Calculate peak amplitude & RMS energy to detect silence/empty audio
        var maxAmplitude: Float = 0
        var sumSquares: Float = 0
        for sample in audioFrames {
            let absSample = abs(sample)
            if absSample > maxAmplitude {
                maxAmplitude = absSample
            }
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(max(1, audioFrames.count)))
        
        // If amplitude or RMS energy is essentially zero, skip to prevent saving blank files
        guard maxAmplitude > 0.012 && rms > 0.003 else {
            print("🔕 Audio is silent (max amp: \(maxAmplitude), rms: \(rms)). Discarded without saving.")
            updateIcon(symbol: "mic")
            return
        }

        updateIcon(symbol: (mode == .memoryVault) ? "brain.fill" : "waveform.circle")
        print("🧠 Transcribing \(audioFrames.count) frames locally (Mode: \(mode), amp: \(maxAmplitude))...")

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

            if mode == .standard {
                await self.textInjector.startProcessingAnimation()
            }

            do {
                let text = try await transcriber.transcribe(audioFrames: audioFrames)

                if mode == .standard {
                    await self.textInjector.stopProcessingAnimation()
                }

                // Check abort after transcription completes
                guard !self.abortRequested else {
                    print("🚫 Transcription result discarded (abort requested).")
                    self.updateIcon(symbol: "mic")
                    return
                }

                // Check if the transcription contains actual meaningful speech
                guard self.isMeaningfulSpeech(text: text, audioFrames: audioFrames) else {
                    print("🔕 Silence or empty speech detected ('\(text)'). Discarded without saving.")
                    self.updateIcon(symbol: "mic")
                    return
                }

                if mode == .standard {
                    print("✅ Transcribed: \(text)")
                    self.historyWindowController.appendTranscription(text)
                    // Append trailing space so consecutive dictations don't merge
                    self.textInjector.injectText(text + " ")
                } else {
                    let lapIndex = lap ?? self.lapManager.currentLap
                    print("🧠 Archiving voice conversation note (Part \(lapIndex)): \(text)")
                    do {
                        try self.conversationStorage.saveConversation(
                            audioFrames: audioFrames,
                            transcription: text,
                            lap: lapIndex
                        )
                    } catch {
                        print("❌ Failed to archive voice conversation note: \(error)")
                    }
                    self.historyWindowController.appendTranscription("🧠 [Part \(lapIndex)] " + text)
                }

                self.updateIcon(symbol: "mic")

            } catch {
                if mode == .standard {
                    await self.textInjector.stopProcessingAnimation()
                }
                print("❌ Transcription error: \(error)")
                self.updateIcon(symbol: "mic")
            }
        }
    }

    private func processLapRecording(lap: Int, audioFrames: [Float]) {
        guard let transcriber = self.transcriber, !audioFrames.isEmpty else { return }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let text = try await transcriber.transcribe(audioFrames: audioFrames)
                guard !self.abortRequested else { return }
                guard self.isMeaningfulSpeech(text: text, audioFrames: audioFrames) else {
                    print("🔕 Lap \(lap) contained silence. Discarded.")
                    return
                }

                print("🧠 Archiving completed Lap \(lap): \(text)")
                do {
                    try self.conversationStorage.saveConversation(
                        audioFrames: audioFrames,
                        transcription: text,
                        lap: lap
                    )
                } catch {
                    print("❌ Failed to archive Lap \(lap): \(error)")
                }
                self.historyWindowController.appendTranscription("🧠 [Part \(lap)] " + text)
            } catch {
                print("❌ Lap \(lap) transcription error: \(error)")
            }
        }
    }

    /// Validates whether transcribed text and audio frames represent meaningful speech rather than silence/artifacts.
    private func isMeaningfulSpeech(text: String, audioFrames: [Float]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }

        // Must contain at least 2 alphanumeric characters
        let alphanumericCount = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        if alphanumericCount < 2 {
            return false
        }

        // Filter common Whisper silence hallucination patterns
        let lower = trimmed.lowercased()
        let silenceHallucinations: Set<String> = [
            "[music]", "[silence]", "(music)", "(silence)", "[applause]", "[blank_audio]",
            "thank you.", "thank you", "thanks for watching!", "thanks for watching.",
            "subtitles by", "subtitles by the amara.org community", "you", "bye.", "bye!"
        ]
        if silenceHallucinations.contains(lower) {
            return false
        }

        return true
    }

    // MARK: - Helpers

    private func updateIcon(symbol: String) {
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true  // Adapts to light/dark mode
            self.statusItem.button?.image = image
            self.statusItem.button?.title = ""
        }
    }
    private func effectiveMode(from detected: DictationMode) -> DictationMode {
        switch activeMode {
        case .smartDual:
            return detected
        case .directOnly:
            return .standard
        case .conversationOnly:
            return .memoryVault
        }
    }

    private func setupHistoryWindow() {
        historyWindowController.onMicPressed = { [weak self] requestedMode in
            guard let self else { return }
            let mode = self.effectiveMode(from: requestedMode ?? .standard)
            if self.audioRecorder.isRecording {
                self.keyboardListenerDidStopRecording(mode: mode)
            } else {
                self.keyboardListenerDidStartRecording(mode: mode)
            }
        }

        historyWindowController.onSettingsPressed = { [weak self] view in
            guard let self else { return }
            self.showModelMenu(anchoredAt: view)
        }
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

            let item = NSMenuItem(title: itemTitle, action: #selector(modelMenuItemClicked(_:)), keyEquivalent: "")
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

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    @objc private func openModelFolder() {
        let dir = WhisperTranscriber.defaultModelDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func modelMenuItemClicked(_ sender: NSMenuItem) {
        guard let filename = sender.representedObject as? String else { return }
        switchModel(filename: filename)
    }
}

// MARK: - KeyboardListenerDelegate

extension App: KeyboardListenerDelegate {
    func keyboardListenerDidStartRecording(mode detectedMode: DictationMode) {
        let mode = effectiveMode(from: detectedMode)

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
        updateIcon(symbol: (mode == .memoryVault) ? "waveform.and.mic" : "waveform.circle")
        historyWindowController.setRecording(true)

        if mode == .memoryVault {
            lapManager.startSession()
            lapTimer?.invalidate()
            lapTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.lapManager.evaluateLapRollover()
                }
            }
        }

        FloatingRecordingIndicator.shared.show(mode: mode, lap: mode == .memoryVault ? lapManager.currentLap : 1)

        do {
            try audioRecorder.startRecording()
            if mode == .memoryVault {
                print("🎙️ Recording Hands-Free Voice Conversation Memo (Mode: \(activeMode.rawValue))...")
            } else {
                print("🎙️ Recording Direct Dictation (Mode: \(activeMode.rawValue))...")
            }
        } catch {
            print("❌ Failed to start recording: \(error)")
            updateIcon(symbol: "mic")
        }
    }

    func keyboardListenerDidStopRecording(mode detectedMode: DictationMode) {
        let mode = effectiveMode(from: detectedMode)
        print("⏹️  Recording stopped. Processing (Mode: \(mode))...")
        lapTimer?.invalidate()
        lapTimer = nil
        let (finalLap, _) = (mode == .memoryVault) ? lapManager.stopSession() : (1, 0.0)

        historyWindowController.setRecording(false)
        FloatingRecordingIndicator.shared.hide()
        processRecording(mode: mode, lap: (mode == .memoryVault) ? finalLap : nil)
    }

    func keyboardListenerDidAbort() {
        abortRequested = true
        lapTimer?.invalidate()
        lapTimer = nil
        _ = lapManager.stopSession()
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
