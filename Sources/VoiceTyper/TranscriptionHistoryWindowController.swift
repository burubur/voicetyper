import Cocoa
import Foundation

// MARK: - TranscriptionHistoryItem

struct TranscriptionHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - RecordedConversationItem

struct RecordedConversationItem: Identifiable, Equatable {
    let id: String
    let filename: String
    let dateFormatted: String
    let timeFormatted: String
    let wavURL: URL
    let txtURL: URL?
    let transcriptPreview: String
    let createdAt: Date
    let fileSizeString: String
}

// MARK: - TranscriptionHistoryWindowController

@MainActor
final class TranscriptionHistoryWindowController: NSWindowController, NSTextFieldDelegate {
    var onMicPressed: ((DictationMode?) -> Void)?
    var onClearPressed: (() -> Void)?
    var onSettingsPressed: ((NSView) -> Void)?

    private var items: [TranscriptionHistoryItem] = []
    private var filteredItems: [TranscriptionHistoryItem] = []
    private var recordedConversations: [RecordedConversationItem] = []
    private var isRecording = false

    private let contentView = ThemeAwareView()
    private let tabSegmentedControl: NSSegmentedControl = {
        let sc = NSSegmentedControl(labels: ["Transcriptions", "Conversations"], trackingMode: .selectOne, target: nil, action: nil)
        sc.selectedSegment = 0
        sc.segmentStyle = .texturedRounded
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.font = .systemFont(ofSize: 12, weight: .medium)
        return sc
    }()

    private let searchField = NSTextField()
    private let searchPill = NSView()

    private let conversationsHeaderBar: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 8
        stack.isHidden = true
        return stack
    }()

    private let conversationsPathLabel: NSTextField = {
        let lbl = NSTextField(labelWithString: "~/.voicetyper/conversation")
        lbl.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        lbl.textColor = Palette.secondaryText
        lbl.lineBreakMode = .byTruncatingHead
        return lbl
    }()

    private let scrollView = NSScrollView()
    private let cardsStack = NSStackView()
    private let recordButton = CircleRecordButton()
    private let onboardingOverlay = NSVisualEffectView()
    private let onboardingProgress = NSProgressIndicator()
    private let onboardingStatus = NSTextField(labelWithString: "Preparing download...")
    
    private let downloadingStatusBar: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        stack.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.layer?.borderWidth = 1
        stack.isHidden = true
        return stack
    }()
    private let downloadingStatusLabel: NSTextField = {
        let lbl = NSTextField(labelWithString: "Downloading...")
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = Palette.secondaryText
        return lbl
    }()
    private let downloadingStatusProgress: NSProgressIndicator = {
        let p = NSProgressIndicator()
        p.style = .spinning
        p.controlSize = .small
        p.translatesAutoresizingMaskIntoConstraints = false
        p.isIndeterminate = true
        return p
    }()

    private let emptyStateStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 42, weight: .thin))
        icon.contentTintColor = Palette.secondaryText.withAlphaComponent(0.5)
        
        let label = NSTextField(labelWithString: "No transcriptions yet")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = Palette.secondaryText
        
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.alphaValue = 0.8
        return stack
    }()
    private let bottomBar = ThemeAwareView()
    private lazy var settingsButton = iconButton(symbol: "gearshape", action: #selector(settingsButtonPressed))

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH.mm"
        return formatter
    }()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceTyper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Palette.windowBackground
        window.minSize = NSSize(width: 420, height: 540)
        window.center()

        super.init(window: window)

        setupContent()
        loadHistory()
        applyFilter()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        if tabSegmentedControl.selectedSegment == 1 {
            loadRecordedConversations()
            renderCards()
        }
    }

    func appendTranscription(_ text: String, createdAt: Date = Date()) {
        let item = TranscriptionHistoryItem(text: text, createdAt: createdAt)
        items.insert(item, at: 0)
        saveHistory()

        if tabSegmentedControl.selectedSegment == 0 {
            let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty || text.localizedCaseInsensitiveContains(query) {
                filteredItems.insert(item, at: 0)
                
                let card = TranscriptionCardView(
                    item: item,
                    date: dateFormatter.string(from: item.createdAt),
                    time: timeFormatter.string(from: item.createdAt),
                    onCopy: { text in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    },
                    onDelete: { [weak self] id in
                        self?.deleteTranscription(id: id)
                    }
                )
                card.translatesAutoresizingMaskIntoConstraints = false
                card.alphaValue = 0.0
                
                cardsStack.insertArrangedSubview(card, at: 0)
                
                NSLayoutConstraint.activate([
                    card.widthAnchor.constraint(equalTo: cardsStack.widthAnchor),
                    card.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
                ])
                
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.4
                    context.allowsImplicitAnimation = true
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    card.animator().alphaValue = 1.0
                    self.cardsStack.superview?.layoutSubtreeIfNeeded()
                })
                
                emptyStateStack.isHidden = true
            }
        } else {
            loadRecordedConversations()
            renderCards()
        }
    }

    func deleteTranscription(id: UUID) {
        items.removeAll { $0.id == id }
        filteredItems.removeAll { $0.id == id }
        saveHistory()
        
        if let view = cardsStack.arrangedSubviews.first(where: { ($0 as? TranscriptionCardView)?.item.id == id }) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().alphaValue = 0.0
                if let heightConstraint = view.constraints.first(where: { $0.firstAttribute == .height }) {
                    heightConstraint.animator().constant = 0
                }
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.cardsStack.removeArrangedSubview(view)
                    view.removeFromSuperview()
                    if self.filteredItems.isEmpty {
                        self.emptyStateStack.isHidden = false
                    }
                }
            })
        } else {
            applyFilter()
        }
    }

    func setDownloadingState(modelName: String?) {
        if let name = modelName {
            downloadingStatusLabel.stringValue = "Downloading \(name)..."
            downloadingStatusBar.isHidden = false
            downloadingStatusProgress.startAnimation(nil)
        } else {
            downloadingStatusBar.isHidden = true
            downloadingStatusProgress.stopAnimation(nil)
        }
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        recordButton.setRecording(recording)
    }

    func clearHistory() {
        if tabSegmentedControl.selectedSegment == 0 {
            let alert = NSAlert()
            alert.messageText = "Clear History"
            alert.informativeText = "Are you sure you want to clear all transcription history?"
            alert.addButton(withTitle: "Clear All")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning

            if alert.runModal() == .alertFirstButtonReturn {
                items.removeAll()
                saveHistory()
                applyFilter()
                onClearPressed?()
            }
        } else {
            openConversationFolderClicked()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    // MARK: - Persistence

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "transcription_history")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "transcription_history") else { return }
        do {
            items = try JSONDecoder().decode([TranscriptionHistoryItem].self, from: data)
        } catch {
            print("⚠️ Failed to decode transcription history: \(error). Resetting history store.")
            UserDefaults.standard.removeObject(forKey: "transcription_history")
            items = []
        }
    }

    // MARK: - Recorded Conversation Loading

    private func loadRecordedConversations() {
        let baseDir = VoiceConversationStorage.defaultBaseDirectory
        var results: [RecordedConversationItem] = []

        guard FileManager.default.fileExists(atPath: baseDir.path) else {
            self.recordedConversations = []
            return
        }

        let enumerator = FileManager.default.enumerator(
            at: baseDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "wav" {
                let filename = fileURL.deletingPathExtension().lastPathComponent
                let txtURL = fileURL.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("text")
                    .appendingPathComponent("\(filename).txt")

                var preview = ""
                if FileManager.default.fileExists(atPath: txtURL.path),
                   let textContent = try? String(contentsOf: txtURL, encoding: .utf8) {
                    preview = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                var createdAt = Date()
                var sizeString = "Audio (.wav)"
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) {
                    if let modDate = resourceValues.contentModificationDate {
                        createdAt = modDate
                    }
                    if let size = resourceValues.fileSize {
                        let kb = Double(size) / 1024.0
                        if kb > 1024 {
                            sizeString = String(format: "%.1f MB", kb / 1024.0)
                        } else {
                            sizeString = String(format: "%.0f KB", kb)
                        }
                    }
                }

                let item = RecordedConversationItem(
                    id: filename,
                    filename: filename,
                    dateFormatted: dateFormatter.string(from: createdAt),
                    timeFormatted: timeFormatter.string(from: createdAt),
                    wavURL: fileURL,
                    txtURL: FileManager.default.fileExists(atPath: txtURL.path) ? txtURL : nil,
                    transcriptPreview: preview.isEmpty ? "(Voice memo audio recording)" : preview,
                    createdAt: createdAt,
                    fileSizeString: sizeString
                )
                results.append(item)
            }
        }

        // Sort descending by creation date
        results.sort { $0.createdAt > $1.createdAt }
        self.recordedConversations = results
    }

    // MARK: - Layout Setup

    private func setupContent() {
        guard let window else { return }

        contentView.wantsLayer = true
        contentView.onAppearanceChanged = { [weak self] in
            self?.refreshColors()
        }
        window.contentView = contentView

        setupTabs()
        setupSearchField()
        setupConversationsHeader()
        setupBottomBar()
        setupScrollView()
        setupOnboardingOverlay()
        refreshColors()
    }

    private func setupTabs() {
        tabSegmentedControl.target = self
        tabSegmentedControl.action = #selector(tabChanged(_:))
        contentView.addSubview(tabSegmentedControl)

        NSLayoutConstraint.activate([
            tabSegmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 46),
            tabSegmentedControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            tabSegmentedControl.heightAnchor.constraint(equalToConstant: 28),
            tabSegmentedControl.widthAnchor.constraint(equalToConstant: 240)
        ])
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        let isConversations = (sender.selectedSegment == 1)
        searchPill.isHidden = isConversations
        conversationsHeaderBar.isHidden = !isConversations
        recordButton.setMode(isConversation: isConversations)

        if isConversations {
            loadRecordedConversations()
        }
        renderCards()
    }

    private func setupSearchField() {
        searchPill.translatesAutoresizingMaskIntoConstraints = false
        searchPill.wantsLayer = true
        searchPill.layer?.cornerRadius = 18
        searchPill.layer?.borderWidth = 1
        searchPill.layer?.shadowColor = NSColor.black.cgColor
        searchPill.layer?.shadowOpacity = 0.08
        searchPill.layer?.shadowOffset = NSSize(width: 0, height: -2)
        searchPill.layer?.shadowRadius = 6

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.placeholderString = "Search transcriptions..."
        searchField.font = .systemFont(ofSize: 13, weight: .regular)
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.isBezeled = false

        searchPill.addSubview(searchField)
        contentView.addSubview(searchPill)

        NSLayoutConstraint.activate([
            searchPill.topAnchor.constraint(equalTo: tabSegmentedControl.bottomAnchor, constant: 14),
            searchPill.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchPill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            searchPill.heightAnchor.constraint(equalToConstant: 36),

            searchField.leadingAnchor.constraint(equalTo: searchPill.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: searchPill.trailingAnchor, constant: -16),
            searchField.centerYAnchor.constraint(equalTo: searchPill.centerYAnchor),
        ])
    }

    private func setupConversationsHeader() {
        let openFolderBtn = NSButton(title: "Open in Finder", target: self, action: #selector(openConversationFolderClicked))
        openFolderBtn.bezelStyle = .rounded
        openFolderBtn.font = .systemFont(ofSize: 11, weight: .medium)
        if let folderImg = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
            folderImg.size = NSSize(width: 14, height: 14)
            openFolderBtn.image = folderImg
            openFolderBtn.imagePosition = .imageLeading
        }

        let refreshBtn = NSButton(title: "", target: self, action: #selector(refreshConversationsClicked))
        refreshBtn.bezelStyle = .rounded
        if let refreshImg = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil) {
            refreshImg.size = NSSize(width: 12, height: 12)
            refreshBtn.image = refreshImg
            refreshBtn.imagePosition = .imageOnly
        }

        conversationsHeaderBar.addArrangedSubview(conversationsPathLabel)
        conversationsHeaderBar.addArrangedSubview(refreshBtn)
        conversationsHeaderBar.addArrangedSubview(openFolderBtn)
        contentView.addSubview(conversationsHeaderBar)

        NSLayoutConstraint.activate([
            conversationsHeaderBar.topAnchor.constraint(equalTo: tabSegmentedControl.bottomAnchor, constant: 14),
            conversationsHeaderBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            conversationsHeaderBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            conversationsHeaderBar.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @objc private func openConversationFolderClicked() {
        let dir = VoiceConversationStorage.defaultBaseDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func refreshConversationsClicked() {
        loadRecordedConversations()
        renderCards()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.scrollerStyle = .overlay

        cardsStack.translatesAutoresizingMaskIntoConstraints = false
        cardsStack.orientation = .vertical
        cardsStack.alignment = .width
        cardsStack.spacing = 14
        cardsStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(cardsStack)
        scrollView.documentView = documentView

        emptyStateStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(emptyStateStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: searchPill.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            cardsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            cardsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            cardsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            cardsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            emptyStateStack.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.wantsLayer = true
        contentView.addSubview(bottomBar)

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.target = self
        recordButton.action = #selector(recordButtonPressed)

        let clearButton = iconButton(symbol: "trash", action: #selector(clearButtonPressed))

        bottomBar.addSubview(recordButton)
        bottomBar.addSubview(clearButton)
        bottomBar.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 76),

            recordButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            recordButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            recordButton.heightAnchor.constraint(equalToConstant: 42),

            clearButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -16),
            settingsButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),
            clearButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
        ])
    }

    private func setupOnboardingOverlay() {
        onboardingOverlay.translatesAutoresizingMaskIntoConstraints = false
        onboardingOverlay.material = .popover
        onboardingOverlay.blendingMode = .withinWindow
        onboardingOverlay.state = .active
        onboardingOverlay.isHidden = true
        onboardingOverlay.wantsLayer = true
        onboardingOverlay.layer?.zPosition = 100
        contentView.addSubview(onboardingOverlay)
        
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        onboardingOverlay.addSubview(stack)
        
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 48, weight: .thin))
        icon.contentTintColor = Palette.accentGreen
        
        let title = NSTextField(labelWithString: "Downloading Voice Model")
        title.font = .systemFont(ofSize: 20, weight: .medium)
        title.textColor = Palette.primaryText
        
        let desc = NSTextField(wrappingLabelWithString: "Downloading the Whisper speech model. This runs 100% locally on your Mac for total privacy. It will only take a moment.")
        desc.font = .systemFont(ofSize: 13, weight: .regular)
        desc.textColor = Palette.secondaryText
        desc.alignment = .center
        desc.preferredMaxLayoutWidth = 280
        
        onboardingProgress.controlSize = .regular
        onboardingProgress.style = .bar
        onboardingProgress.isIndeterminate = false
        onboardingProgress.minValue = 0
        onboardingProgress.maxValue = 1.0
        onboardingProgress.translatesAutoresizingMaskIntoConstraints = false
        
        onboardingStatus.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        onboardingStatus.textColor = Palette.secondaryText
        
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(desc)
        stack.setCustomSpacing(24, after: desc)
        stack.addArrangedSubview(onboardingProgress)
        stack.addArrangedSubview(onboardingStatus)
        
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelDownloadClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.font = .systemFont(ofSize: 13, weight: .regular)
        stack.setCustomSpacing(16, after: onboardingStatus)
        stack.addArrangedSubview(cancelBtn)
        
        NSLayoutConstraint.activate([
            onboardingOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            onboardingOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            onboardingOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            onboardingOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            stack.centerXAnchor.constraint(equalTo: onboardingOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: onboardingOverlay.centerYAnchor),
            
            onboardingProgress.widthAnchor.constraint(equalToConstant: 240)
        ])
    }
    
    @objc private func cancelDownloadClicked() {
        ModelDownloader.shared.cancelDownload()
    }
    
    func startOnboardingDownload(completion: @escaping @Sendable (Bool) -> Void) {
        onboardingOverlay.isHidden = false
        onboardingOverlay.alphaValue = 1.0
        
        ModelDownloader.shared.progressCallback = { [weak self] progress, status in
            self?.onboardingProgress.doubleValue = progress
            self?.onboardingStatus.stringValue = status
        }
        
        ModelDownloader.shared.checkAndDownloadModel { [weak self] success in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                self?.onboardingOverlay.animator().alphaValue = 0.0
            }, completionHandler: {
                Task { @MainActor in
                    self?.onboardingOverlay.isHidden = true
                    completion(success)
                }
            })
        }
    }

    private func iconButton(symbol: String, action: Selector) -> IconButton {
        let button = IconButton(symbol: symbol)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { $0.text.localizedCaseInsensitiveContains(query) }
        }
        if tabSegmentedControl.selectedSegment == 0 {
            renderCards()
        }
    }

    private func refreshColors() {
        window?.backgroundColor = Palette.windowBackground
        contentView.layer?.backgroundColor = Palette.windowBackground.cgColor
        bottomBar.layer?.backgroundColor = Palette.windowBackground.cgColor
        searchField.textColor = Palette.primaryText
        searchPill.layer?.backgroundColor = Palette.searchBackground.cgColor
        searchPill.layer?.borderColor = Palette.border.cgColor
        recordButton.refreshColors()
        cardsStack.arrangedSubviews.forEach { view in
            (view as? TranscriptionCardView)?.refreshColors()
            (view as? ConversationCardView)?.refreshColors()
        }
    }

    func deleteConversation(filename: String) {
        guard let item = recordedConversations.first(where: { $0.filename == filename }) else { return }
        
        let alert = NSAlert()
        alert.messageText = "Delete Voice Recording"
        alert.informativeText = "Are you sure you want to delete '\(filename).wav' and its transcript note?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            try? FileManager.default.removeItem(at: item.wavURL)
            if let txtURL = item.txtURL {
                try? FileManager.default.removeItem(at: txtURL)
            }
            recordedConversations.removeAll { $0.filename == filename }
            renderCards()
        }
    }

    private func renderCards() {
        cardsStack.arrangedSubviews.forEach { view in
            cardsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if tabSegmentedControl.selectedSegment == 0 {
            // Tab 0: Transcriptions
            emptyStateStack.isHidden = !filteredItems.isEmpty
            if let emptyLabel = emptyStateStack.arrangedSubviews.last as? NSTextField {
                emptyLabel.stringValue = "No transcriptions yet"
            }

            for item in filteredItems {
                let card = TranscriptionCardView(
                    item: item,
                    date: dateFormatter.string(from: item.createdAt),
                    time: timeFormatter.string(from: item.createdAt),
                    onCopy: { text in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    },
                    onDelete: { [weak self] id in
                        self?.deleteTranscription(id: id)
                    }
                )
                card.translatesAutoresizingMaskIntoConstraints = false
                cardsStack.addArrangedSubview(card)
                
                NSLayoutConstraint.activate([
                    card.widthAnchor.constraint(equalTo: cardsStack.widthAnchor),
                    card.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
                    card.heightAnchor.constraint(lessThanOrEqualToConstant: 160)
                ])
            }
        } else {
            // Tab 1: Conversations (Voice Memos)
            emptyStateStack.isHidden = !recordedConversations.isEmpty
            if let emptyLabel = emptyStateStack.arrangedSubviews.last as? NSTextField {
                emptyLabel.stringValue = "No voice recordings found in ~/.voicetyper/conversation"
            }

            for item in recordedConversations {
                let card = ConversationCardView(
                    item: item,
                    onOpenInFinder: { wavURL in
                        NSWorkspace.shared.activateFileViewerSelecting([wavURL])
                    },
                    onPlay: { wavURL in
                        NSWorkspace.shared.open(wavURL)
                    },
                    onDelete: { [weak self] filename in
                        self?.deleteConversation(filename: filename)
                    }
                )
                card.translatesAutoresizingMaskIntoConstraints = false
                cardsStack.addArrangedSubview(card)

                NSLayoutConstraint.activate([
                    card.widthAnchor.constraint(equalTo: cardsStack.widthAnchor),
                    card.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
                    card.heightAnchor.constraint(lessThanOrEqualToConstant: 150)
                ])
            }
        }
    }

    @objc private func recordButtonPressed() {
        let mode: DictationMode = (tabSegmentedControl.selectedSegment == 1) ? .memoryVault : .standard
        onMicPressed?(mode)
    }

    @objc private func clearButtonPressed() {
        clearHistory()
    }

    @objc private func settingsButtonPressed() {
        onSettingsPressed?(settingsButton)
    }
}

// MARK: - ConversationCardView

@MainActor
final class ConversationCardView: NSView {
    nonisolated override var isFlipped: Bool { true }
    let item: RecordedConversationItem
    private let onOpenInFinder: (URL) -> Void
    private let onPlay: (URL) -> Void
    private let onDelete: (String) -> Void

    private let titleLabel: NSTextField
    private let previewLabel: NSTextField
    private let dateBadge: NSTextField
    private let timeBadge: NSTextField
    private let sizeBadge: NSTextField
    private let playButton: IconButton
    private let openButton: IconButton
    private let deleteButton: IconButton

    private var trackingArea: NSTrackingArea?

    init(
        item: RecordedConversationItem,
        onOpenInFinder: @escaping (URL) -> Void,
        onPlay: @escaping (URL) -> Void,
        onDelete: @escaping (String) -> Void
    ) {
        self.item = item
        self.onOpenInFinder = onOpenInFinder
        self.onPlay = onPlay
        self.onDelete = onDelete

        self.titleLabel = NSTextField(labelWithString: item.filename + ".wav")
        self.previewLabel = NSTextField(wrappingLabelWithString: item.transcriptPreview)
        self.dateBadge = NSTextField(labelWithString: item.dateFormatted)
        self.timeBadge = NSTextField(labelWithString: item.timeFormatted)
        self.sizeBadge = NSTextField(labelWithString: item.fileSizeString)

        self.playButton = IconButton(symbol: "play.fill")
        self.openButton = IconButton(symbol: "folder")
        self.deleteButton = IconButton(symbol: "trash")

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowRadius = 6

        setupUI()
        refreshColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let micIcon = NSImageView()
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        micIcon.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: nil)
        micIcon.contentTintColor = Palette.accentPurple

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = .systemFont(ofSize: 12, weight: .regular)
        previewLabel.maximumNumberOfLines = 3
        previewLabel.lineBreakMode = .byWordWrapping
        (previewLabel.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true

        dateBadge.translatesAutoresizingMaskIntoConstraints = false
        dateBadge.font = .systemFont(ofSize: 11, weight: .medium)

        timeBadge.translatesAutoresizingMaskIntoConstraints = false
        timeBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        sizeBadge.translatesAutoresizingMaskIntoConstraints = false
        sizeBadge.font = .systemFont(ofSize: 10, weight: .medium)
        sizeBadge.textColor = Palette.secondaryText

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.target = self
        playButton.action = #selector(playClicked)
        playButton.alphaValue = 0.0

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.target = self
        openButton.action = #selector(openClicked)
        openButton.alphaValue = 0.0

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.alphaValue = 0.0

        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .separator
        divider.alphaValue = 0.4

        addSubview(micIcon)
        addSubview(titleLabel)
        addSubview(sizeBadge)
        addSubview(previewLabel)
        addSubview(divider)
        addSubview(dateBadge)
        addSubview(timeBadge)
        addSubview(playButton)
        addSubview(openButton)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            micIcon.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            micIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            micIcon.widthAnchor.constraint(equalToConstant: 18),
            micIcon.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.centerYAnchor.constraint(equalTo: micIcon.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: micIcon.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: sizeBadge.leadingAnchor, constant: -8),

            sizeBadge.centerYAnchor.constraint(equalTo: micIcon.centerYAnchor),
            sizeBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            divider.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            dateBadge.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            dateBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            timeBadge.centerYAnchor.constraint(equalTo: dateBadge.centerYAnchor),
            timeBadge.leadingAnchor.constraint(equalTo: dateBadge.trailingAnchor, constant: 8),
            timeBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            deleteButton.centerYAnchor.constraint(equalTo: dateBadge.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),

            openButton.centerYAnchor.constraint(equalTo: dateBadge.centerYAnchor),
            openButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            openButton.widthAnchor.constraint(equalToConstant: 22),
            openButton.heightAnchor.constraint(equalToConstant: 22),

            playButton.centerYAnchor.constraint(equalTo: dateBadge.centerYAnchor),
            playButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
            playButton.widthAnchor.constraint(equalToConstant: 22),
            playButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            playButton.animator().alphaValue = 1.0
            openButton.animator().alphaValue = 1.0
            deleteButton.animator().alphaValue = 1.0
            layer?.borderColor = Palette.accentPurple.withAlphaComponent(0.6).cgColor
            layer?.shadowOpacity = 0.16
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            playButton.animator().alphaValue = 0.0
            openButton.animator().alphaValue = 0.0
            deleteButton.animator().alphaValue = 0.0
            layer?.borderColor = Palette.border.cgColor
            layer?.shadowOpacity = 0.08
        }
    }

    @objc private func openClicked() {
        onOpenInFinder(item.wavURL)
    }

    @objc private func playClicked() {
        onPlay(item.wavURL)
    }

    @objc private func deleteClicked() {
        onDelete(item.filename)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func refreshColors() {
        layer?.backgroundColor = Palette.cardBackground.cgColor
        layer?.borderColor = Palette.border.cgColor
        titleLabel.textColor = Palette.primaryText
        previewLabel.textColor = Palette.secondaryText
        dateBadge.textColor = Palette.secondaryText
        timeBadge.textColor = Palette.secondaryText
        playButton.refreshColors()
        openButton.refreshColors()
        deleteButton.refreshColors()
    }
}

// MARK: - TranscriptionCardView

@MainActor
class TranscriptionCardView: NSView {
    nonisolated override var isFlipped: Bool { true }
    let item: TranscriptionHistoryItem
    private let onCopy: (String) -> Void
    private let onDelete: (UUID) -> Void

    private let textLabel: NSTextField
    private let dateLabel: NSTextField
    private let timeLabel: NSTextField
    private let copyButton: IconButton
    private let deleteButton: IconButton
    private let toastLabel: NSTextField

    private var trackingArea: NSTrackingArea?

    init(item: TranscriptionHistoryItem, date: String, time: String, onCopy: @escaping (String) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.onCopy = onCopy
        self.onDelete = onDelete

        self.textLabel = NSTextField(wrappingLabelWithString: item.text)
        self.dateLabel = NSTextField(labelWithString: date)
        self.timeLabel = NSTextField(labelWithString: time)
        self.copyButton = IconButton(symbol: "doc.on.doc")
        self.deleteButton = IconButton(symbol: "trash")
        self.toastLabel = NSTextField(labelWithString: "Copied!")

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowRadius = 6

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .systemFont(ofSize: 13, weight: .regular)
        textLabel.maximumNumberOfLines = 4
        textLabel.lineBreakMode = .byWordWrapping
        (textLabel.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true

        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .separator
        divider.alphaValue = 0.5

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 11, weight: .semibold)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.alphaValue = 0.0

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.alphaValue = 0.0

        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.font = .systemFont(ofSize: 11, weight: .bold)
        toastLabel.textColor = Palette.accentGreen
        toastLabel.alphaValue = 0.0

        addSubview(textLabel)
        addSubview(copyButton)
        addSubview(deleteButton)
        addSubview(toastLabel)
        addSubview(divider)
        addSubview(dateLabel)
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            textLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),

            copyButton.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            copyButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            copyButton.widthAnchor.constraint(equalToConstant: 22),
            copyButton.heightAnchor.constraint(equalToConstant: 22),

            deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),

            toastLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -6),
            toastLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),

            divider.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 18),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            dateLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            timeLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])

        refreshColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            copyButton.animator().alphaValue = 1.0
            deleteButton.animator().alphaValue = 1.0
        }
        let shadowAnim = CABasicAnimation(keyPath: "shadowOpacity")
        shadowAnim.fromValue = layer?.shadowOpacity
        shadowAnim.toValue = 0.15
        shadowAnim.duration = 0.15
        layer?.add(shadowAnim, forKey: "shadowOpacity")
        layer?.shadowOpacity = 0.15
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            copyButton.animator().alphaValue = 0.0
            deleteButton.animator().alphaValue = 0.0
        }
        let shadowAnim = CABasicAnimation(keyPath: "shadowOpacity")
        shadowAnim.fromValue = layer?.shadowOpacity
        shadowAnim.toValue = 0.08
        shadowAnim.duration = 0.2
        layer?.add(shadowAnim, forKey: "shadowOpacity")
        layer?.shadowOpacity = 0.08
    }

    @objc private func copyClicked() {
        onCopy(item.text)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            toastLabel.animator().alphaValue = 1.0
        } completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self?.toastLabel.animator().alphaValue = 0.0
                }
            }
        }
    }

    @objc private func deleteClicked() {
        onDelete(item.id)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func refreshColors() {
        layer?.backgroundColor = Palette.cardBackground.cgColor
        layer?.borderColor = Palette.border.cgColor
        textLabel.textColor = Palette.primaryText
        dateLabel.textColor = Palette.secondaryText
        timeLabel.textColor = Palette.secondaryText
    }
}

// MARK: - IconButton

class IconButton: NSButton {
    init(symbol: String) {
        super.init(frame: .zero)
        if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            symbolImage.size = NSSize(width: 16, height: 16)
            image = symbolImage
        }
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        isBordered = false
        wantsLayer = false
        refreshColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func refreshColors() {
        contentTintColor = Palette.secondaryText
    }
}

// MARK: - CircleRecordButton

class CircleRecordButton: NSButton {
    private var recording = false
    private var isConversationMode = false
    private let coralColor = NSColor(red: 253 / 255.0, green: 121 / 255.0, blue: 121 / 255.0, alpha: 1.0)
    private let purpleColor = NSColor(red: 168 / 255.0, green: 85 / 255.0, blue: 247 / 255.0, alpha: 1.0)

    private let pillView = NSView()
    private let micImageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Right Option and hold to record")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        imagePosition = .noImage
        title = ""
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 20
        pillView.layer?.borderWidth = 1.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowRadius = 6
        pillView.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        pillView.layer?.shadowColor = NSColor.black.cgColor
        pillView.layer?.shadowOpacity = 0.4
        pillView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        pillView.layer?.shadowRadius = 4

        let micImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        micImageView.translatesAutoresizingMaskIntoConstraints = false
        micImageView.image = micImage
        micImageView.contentTintColor = .white
        micImageView.imageScaling = .scaleProportionallyUpOrDown

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .left

        pillView.addSubview(micImageView)
        pillView.addSubview(statusLabel)
        addSubview(pillView)

        NSLayoutConstraint.activate([
            pillView.topAnchor.constraint(equalTo: topAnchor),
            pillView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillView.trailingAnchor.constraint(equalTo: trailingAnchor),

            micImageView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 18),
            micImageView.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            micImageView.widthAnchor.constraint(equalToConstant: 16),
            micImageView.heightAnchor.constraint(equalToConstant: 18),

            statusLabel.leadingAnchor.constraint(equalTo: micImageView.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -18),
            statusLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
        ])

        refreshColors()
    }

    func setMode(isConversation: Bool) {
        self.isConversationMode = isConversation
        updateLabel()
        refreshColors()
    }

    func setRecording(_ value: Bool) {
        recording = value
        updateLabel()
        refreshColors()
    }

    private func updateLabel() {
        if recording {
            statusLabel.stringValue = "Recording..."
        } else if isConversationMode {
            statusLabel.stringValue = "Shift + Right Option to record memo"
        } else {
            statusLabel.stringValue = "Right Option and hold to record"
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func refreshColors() {
        guard let layer = pillView.layer else { return }
        let activeColor = isConversationMode ? purpleColor : coralColor

        if recording {
            layer.backgroundColor = activeColor.withAlphaComponent(0.85).cgColor

            let pulse = CABasicAnimation(keyPath: "backgroundColor")
            pulse.fromValue = activeColor.withAlphaComponent(0.95).cgColor
            pulse.toValue = activeColor.withAlphaComponent(0.35).cgColor
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "recordingPulse")
        } else {
            layer.removeAnimation(forKey: "recordingPulse")
            layer.backgroundColor = activeColor.withAlphaComponent(0.85).cgColor
        }
    }
}

// MARK: - ThemeAwareView

class FlippedView: NSView {
    nonisolated override var isFlipped: Bool { true }
}

class ThemeAwareView: NSView {
    var onAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}

// MARK: - Palette

private enum Palette {
    static let windowBackground = dynamic(
        dark: NSColor(calibratedRed: 0.145, green: 0.145, blue: 0.145, alpha: 1),
        light: NSColor(calibratedWhite: 0.94, alpha: 1)
    )
    static let searchBackground = dynamic(
        dark: NSColor(calibratedRed: 0.205, green: 0.205, blue: 0.205, alpha: 1),
        light: NSColor(calibratedWhite: 0.985, alpha: 1)
    )
    static let cardBackground = dynamic(
        dark: NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.105, alpha: 1),
        light: NSColor(calibratedWhite: 1, alpha: 1)
    )
    static let controlBackground = dynamic(
        dark: NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.22, alpha: 1),
        light: NSColor(calibratedWhite: 0.89, alpha: 1)
    )
    static let border = dynamic(
        dark: NSColor(calibratedWhite: 0.35, alpha: 0.55),
        light: NSColor(calibratedWhite: 0.66, alpha: 0.55)
    )
    static let primaryText = dynamic(
        dark: NSColor(calibratedWhite: 0.84, alpha: 1),
        light: NSColor(calibratedWhite: 0.16, alpha: 1)
    )
    static let secondaryText = dynamic(
        dark: NSColor(calibratedWhite: 0.64, alpha: 1),
        light: NSColor(calibratedWhite: 0.43, alpha: 1)
    )
    static let recordIdle = dynamic(
        dark: NSColor(calibratedWhite: 0.93, alpha: 1),
        light: NSColor(calibratedWhite: 0.12, alpha: 1)
    )
    static let recordIdleText = dynamic(
        dark: NSColor(calibratedWhite: 0.12, alpha: 1),
        light: NSColor(calibratedWhite: 0.93, alpha: 1)
    )
    static let recording = NSColor(calibratedRed: 0.99, green: 0.38, blue: 0.36, alpha: 1)
    static let accentGreen = NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.50, alpha: 1)
    static let accentPurple = NSColor(calibratedRed: 0.65, green: 0.45, blue: 0.95, alpha: 1)

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestMatch == .darkAqua ? dark : light
        }
    }
}
