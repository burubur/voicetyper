import Cocoa
import Foundation

/// Unified macOS Menu Bar Tray Popover Controller.
/// Provides an all-in-one control hub right under the tray icon:
/// - Version & Mode Switcher
/// - Live Recording & Transcribing Status
/// - 1-Click Speech Model Picker
/// - Recent Transcription Card with Copy & Open actions
/// - Quick Action Footer
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
    private var modelStackView: NSStackView?
    private var recentTranscriptLabel: NSTextField?
    private var recentDetailsLabel: NSTextField?
    private var recentCardView: NSView?

    private var lastTranscriptionText: String = ""
    private var lastTranscriptionTime: String = ""
    private var lastTranscriptionDetails: String = ""

    override init() {
        super.init()
        setupPopover()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 420)

        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.frame = NSRect(x: 0, y: 0, width: 360, height: 420)

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
        mainStack.spacing = 12
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        // 1. Header: Title + Version + Mode Switcher
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.distribution = .fill
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "🎙️ VoiceTyper")
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)

        let versionBadge = NSTextField(labelWithString: UpgradeManager.currentVersion)
        versionBadge.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        versionBadge.textColor = .secondaryLabelColor

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

        headerRow.addArrangedSubview(titleLabel)
        headerRow.addArrangedSubview(versionBadge)
        headerRow.addArrangedSubview(NSView()) // spacer
        headerRow.addArrangedSubview(modePopUp)
        mainStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        mainStack.addArrangedSubview(createDivider())

        // 2. Status & Shortcuts Row
        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 6

        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        self.statusDot = dot
        statusRow.addArrangedSubview(dot)
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let status = NSTextField(labelWithString: "Ready")
        status.font = .systemFont(ofSize: 11, weight: .semibold)
        self.statusLabel = status
        statusRow.addArrangedSubview(status)

        statusRow.addArrangedSubview(NSView()) // spacer

        let shortcutHint = NSTextField(labelWithString: "⌥ Hold • ⇧⌥ Memo")
        shortcutHint.font = .systemFont(ofSize: 11, weight: .regular)
        shortcutHint.textColor = .secondaryLabelColor
        statusRow.addArrangedSubview(shortcutHint)

        mainStack.addArrangedSubview(statusRow)
        statusRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        mainStack.addArrangedSubview(createDivider())

        // 3. Speech Model Section
        let modelHeader = NSTextField(labelWithString: "SPEECH MODEL")
        modelHeader.font = .systemFont(ofSize: 10, weight: .bold)
        modelHeader.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(modelHeader)

        let modelStack = NSStackView()
        modelStack.orientation = .vertical
        modelStack.alignment = .leading
        modelStack.spacing = 6
        modelStack.translatesAutoresizingMaskIntoConstraints = false
        self.modelStackView = modelStack
        mainStack.addArrangedSubview(modelStack)
        modelStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        mainStack.addArrangedSubview(createDivider())

        // 4. Recent Transcription Section
        let recentHeader = NSTextField(labelWithString: "RECENT TRANSCRIPTION")
        recentHeader.font = .systemFont(ofSize: 10, weight: .bold)
        recentHeader.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(recentHeader)

        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        self.recentCardView = card

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 6
        cardStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
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
        cardBottomRow.spacing = 8
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
        cardBottomRow.addArrangedSubview(copyBtn)

        cardStack.addArrangedSubview(cardBottomRow)
        cardBottomRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        mainStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        mainStack.addArrangedSubview(createDivider())

        // 5. Footer Actions
        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 8
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        let historyBtn = NSButton(title: "History Window", target: self, action: #selector(historyClicked))
        historyBtn.bezelStyle = .rounded
        historyBtn.font = .systemFont(ofSize: 11, weight: .medium)

        let vaultBtn = NSButton(title: "Vault Folder", target: self, action: #selector(vaultClicked))
        vaultBtn.bezelStyle = .rounded
        vaultBtn.font = .systemFont(ofSize: 11, weight: .medium)

        let quitBtn = NSButton(title: "Quit", target: self, action: #selector(quitClicked))
        quitBtn.bezelStyle = .rounded
        quitBtn.font = .systemFont(ofSize: 11, weight: .medium)

        footerRow.addArrangedSubview(historyBtn)
        footerRow.addArrangedSubview(vaultBtn)
        footerRow.addArrangedSubview(NSView()) // spacer
        footerRow.addArrangedSubview(quitBtn)

        mainStack.addArrangedSubview(footerRow)
        footerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
    }

    private func createDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
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
        rebuildModelList()
    }

    private func rebuildModelList() {
        guard let modelStack = modelStackView else { return }
        modelStack.subviews.forEach { $0.removeFromSuperview() }

        let currentModel = WhisperTranscriber.configuredModelFilename

        for option in WhisperTranscriber.availableModels {
            let isCurrent = option.filename.lowercased() == currentModel.lowercased()
            let isDownloaded = WhisperTranscriber.isModelDownloaded(filename: option.filename)

            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false

            let indicator = NSTextField(labelWithString: isCurrent ? "●" : "○")
            indicator.font = .systemFont(ofSize: 12, weight: .bold)
            indicator.textColor = isCurrent ? NSColor.systemPurple : NSColor.secondaryLabelColor
            row.addArrangedSubview(indicator)

            let nameLabel = NSTextField(labelWithString: "\(option.displayName) (\(option.sizeDescription))")
            nameLabel.font = .systemFont(ofSize: 11, weight: isCurrent ? .bold : .regular)
            row.addArrangedSubview(nameLabel)

            row.addArrangedSubview(NSView()) // spacer

            if isCurrent {
                let badge = NSTextField(labelWithString: "Active")
                badge.font = .systemFont(ofSize: 10, weight: .semibold)
                badge.textColor = .systemGreen
                row.addArrangedSubview(badge)
            } else if isDownloaded {
                let switchBtn = NSButton(title: "Select", target: self, action: #selector(modelButtonClicked(_:)))
                switchBtn.bezelStyle = .rounded
                switchBtn.font = .systemFont(ofSize: 10, weight: .medium)
                switchBtn.identifier = NSUserInterfaceItemIdentifier(rawValue: option.filename)
                row.addArrangedSubview(switchBtn)
            } else {
                let downloadBtn = NSButton(title: "⬇️ Download", target: self, action: #selector(modelButtonClicked(_:)))
                downloadBtn.bezelStyle = .rounded
                downloadBtn.font = .systemFont(ofSize: 10, weight: .medium)
                downloadBtn.identifier = NSUserInterfaceItemIdentifier(rawValue: option.filename)
                row.addArrangedSubview(downloadBtn)
            }

            modelStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: modelStack.widthAnchor).isActive = true
        }
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = ActiveMode(rawValue: raw) else { return }
        onModeChanged?(mode)
    }

    @objc private func modelButtonClicked(_ sender: NSButton) {
        guard let filename = sender.identifier?.rawValue else { return }
        onModelSelected?(filename)
        rebuildModelList()
    }

    @objc private func copyRecentTranscript() {
        guard !lastTranscriptionText.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        _ = pb.setString(lastTranscriptionText, forType: .string)
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
