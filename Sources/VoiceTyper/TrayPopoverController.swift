import Cocoa
import Foundation

/// Ultra-Lightweight, Modern macOS Menu Bar Popover Hub.
/// Engineered with clean glassmorphic depth, refined typography,
/// an inline model dropdown selector, and an actionable recent note card.
@MainActor
final class TrayPopoverController: NSObject {
    private let popover = NSPopover()
    private let contentViewController = NSViewController()

    var onModeChanged: ((ActiveMode) -> Void)?
    var onModelSelected: ((String) -> Void)?
    var onOpenHistory: (() -> Void)?
    var onOpenVault: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusDot: NSView?
    private var statusLabel: NSTextField?
    private var modeButton: NSPopUpButton?
    private var modelPopUp: NSPopUpButton?
    private var recentTranscriptLabel: NSTextField?
    private var recentDetailsLabel: NSTextField?
    private var copyButton: NSButton?

    private var lastTranscriptionText: String = ""
    private var lastTranscriptionDetails: String = ""

    override init() {
        super.init()
        setupPopover()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 265)

        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.frame = NSRect(x: 0, y: 0, width: 320, height: 265)

        buildUI(in: container)
        contentViewController.view = container
        popover.contentViewController = contentViewController
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refreshUI()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func isShown() -> Bool {
        return popover.isShown
    }

    func close() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - UI Construction

    private func buildUI(in root: NSView) {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        // 1. Header: Brand + Version Badge + Mode Switcher
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let brandLabel = NSTextField(labelWithString: "🎙️ VoiceTyper")
        brandLabel.font = .systemFont(ofSize: 13, weight: .bold)

        let versionBadge = createBadge(text: UpgradeManager.currentVersion)

        let modePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopUp.font = .systemFont(ofSize: 11, weight: .medium)
        modePopUp.target = self
        modePopUp.action = #selector(modeChanged(_:))
        for mode in ActiveMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: nil, keyEquivalent: "")
            item.representedObject = mode.rawValue
            modePopUp.menu?.addItem(item)
        }
        self.modeButton = modePopUp

        headerRow.addArrangedSubview(brandLabel)
        headerRow.addArrangedSubview(versionBadge)
        headerRow.addArrangedSubview(NSView()) // spacer
        headerRow.addArrangedSubview(modePopUp)
        mainStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 2. Status & Hotkey Hint Pill Bar
        let statusCard = NSView()
        statusCard.wantsLayer = true
        statusCard.layer?.cornerRadius = 6
        statusCard.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        statusCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        statusCard.layer?.borderWidth = 1
        statusCard.translatesAutoresizingMaskIntoConstraints = false

        let statusStack = NSStackView()
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 6
        statusStack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusStack)

        NSLayoutConstraint.activate([
            statusStack.topAnchor.constraint(equalTo: statusCard.topAnchor),
            statusStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor),
            statusStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor),
            statusStack.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor)
        ])

        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        self.statusDot = dot
        statusStack.addArrangedSubview(dot)
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let status = NSTextField(labelWithString: "Ready")
        status.font = .systemFont(ofSize: 11, weight: .semibold)
        self.statusLabel = status
        statusStack.addArrangedSubview(status)

        statusStack.addArrangedSubview(NSView()) // spacer

        let shortcutHint = NSTextField(labelWithString: "⌥ Hold • ⇧⌥ Memo")
        shortcutHint.font = .systemFont(ofSize: 10, weight: .regular)
        shortcutHint.textColor = .secondaryLabelColor
        statusStack.addArrangedSubview(shortcutHint)

        mainStack.addArrangedSubview(statusCard)
        statusCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 3. Compact Speech Model Dropdown Row
        let modelRow = NSStackView()
        modelRow.orientation = .horizontal
        modelRow.alignment = .centerY
        modelRow.spacing = 8
        modelRow.translatesAutoresizingMaskIntoConstraints = false

        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.font = .systemFont(ofSize: 11, weight: .medium)
        modelLabel.textColor = .secondaryLabelColor

        let modelSelector = NSPopUpButton(frame: .zero, pullsDown: false)
        modelSelector.font = .systemFont(ofSize: 11, weight: .regular)
        modelSelector.target = self
        modelSelector.action = #selector(modelDropdownChanged(_:))
        self.modelPopUp = modelSelector

        modelRow.addArrangedSubview(modelLabel)
        modelRow.addArrangedSubview(modelSelector)
        mainStack.addArrangedSubview(modelRow)
        modelRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 4. Actionable Recent Transcription Card
        let recentCard = NSView()
        recentCard.wantsLayer = true
        recentCard.layer?.cornerRadius = 8
        recentCard.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        recentCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        recentCard.layer?.borderWidth = 1
        recentCard.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 6
        cardStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        recentCard.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: recentCard.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: recentCard.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: recentCard.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: recentCard.bottomAnchor)
        ])

        let transcript = NSTextField(labelWithString: "No transcriptions yet. Press Right Option to speak.")
        transcript.font = .systemFont(ofSize: 11, weight: .regular)
        transcript.textColor = .labelColor
        transcript.maximumNumberOfLines = 3
        transcript.lineBreakMode = .byTruncatingTail
        self.recentTranscriptLabel = transcript
        cardStack.addArrangedSubview(transcript)

        let cardBottomRow = NSStackView()
        cardBottomRow.orientation = .horizontal
        cardBottomRow.alignment = .centerY
        cardBottomRow.spacing = 6
        cardBottomRow.translatesAutoresizingMaskIntoConstraints = false

        let details = NSTextField(labelWithString: "")
        details.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        details.textColor = .secondaryLabelColor
        self.recentDetailsLabel = details
        cardBottomRow.addArrangedSubview(details)

        cardBottomRow.addArrangedSubview(NSView()) // spacer

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyRecentTranscript))
        copyBtn.bezelStyle = .rounded
        copyBtn.font = .systemFont(ofSize: 10, weight: .medium)
        self.copyButton = copyBtn
        cardBottomRow.addArrangedSubview(copyBtn)

        cardStack.addArrangedSubview(cardBottomRow)
        cardBottomRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        mainStack.addArrangedSubview(recentCard)
        recentCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 5. Minimalist Footer Toolbar
        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 6
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        let historyBtn = NSButton(title: "History Window", target: self, action: #selector(historyClicked))
        historyBtn.bezelStyle = .rounded
        historyBtn.font = .systemFont(ofSize: 11, weight: .regular)

        let vaultBtn = NSButton(title: "Vault Folder", target: self, action: #selector(vaultClicked))
        vaultBtn.bezelStyle = .rounded
        vaultBtn.font = .systemFont(ofSize: 11, weight: .regular)

        let quitBtn = NSButton(title: "Quit", target: self, action: #selector(quitClicked))
        quitBtn.bezelStyle = .rounded
        quitBtn.font = .systemFont(ofSize: 11, weight: .regular)

        footerRow.addArrangedSubview(historyBtn)
        footerRow.addArrangedSubview(vaultBtn)
        footerRow.addArrangedSubview(NSView()) // spacer
        footerRow.addArrangedSubview(quitBtn)

        mainStack.addArrangedSubview(footerRow)
        footerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
    }

    private func createBadge(text: String) -> NSView {
        let badge = NSTextField(labelWithString: text)
        badge.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        return badge
    }

    // MARK: - State Updaters

    func updateRecentTranscription(text: String, details: String = "") {
        self.lastTranscriptionText = text
        self.lastTranscriptionDetails = details
        recentTranscriptLabel?.stringValue = text
        recentDetailsLabel?.stringValue = details
    }

    func updateStatus(text: String, color: NSColor) {
        statusLabel?.stringValue = text
        statusDot?.layer?.backgroundColor = color.cgColor
    }

    func updateActiveMode(_ mode: ActiveMode) {
        for item in modeButton?.itemArray ?? [] {
            if let raw = item.representedObject as? String, raw == mode.rawValue {
                modeButton?.select(item)
                break
            }
        }
    }

    func refreshUI() {
        rebuildModelDropdown()
    }

    private func rebuildModelDropdown() {
        guard let popUp = modelPopUp else { return }
        popUp.menu?.removeAllItems()

        let currentModel = WhisperTranscriber.configuredModelFilename

        for option in WhisperTranscriber.availableModels {
            let isCurrent = option.filename.lowercased() == currentModel.lowercased()
            let isDownloaded = WhisperTranscriber.isModelDownloaded(filename: option.filename)
            
            let statusSuffix = isDownloaded ? "" : " (⬇️ Download)"
            let title = "\(option.displayName) — \(option.sizeDescription)\(statusSuffix)"
            
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = option.filename
            popUp.menu?.addItem(item)
            
            if isCurrent {
                popUp.select(item)
            }
        }
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = ActiveMode(rawValue: raw) else { return }
        onModeChanged?(mode)
    }

    @objc private func modelDropdownChanged(_ sender: NSPopUpButton) {
        guard let filename = sender.selectedItem?.representedObject as? String else { return }
        onModelSelected?(filename)
    }

    @objc private func copyRecentTranscript() {
        guard !lastTranscriptionText.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        _ = pb.setString(lastTranscriptionText, forType: .string)

        // Subtle click feedback
        copyButton?.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton?.title = "Copy"
        }
    }

    @objc private func historyClicked() {
        popover.performClose(nil)
        onOpenHistory?()
    }

    @objc private func vaultClicked() {
        popover.performClose(nil)
        onOpenVault?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }
}
