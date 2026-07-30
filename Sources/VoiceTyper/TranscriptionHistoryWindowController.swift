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

// MARK: - TranscriptionHistoryWindowController

@MainActor
final class TranscriptionHistoryWindowController: NSWindowController, NSTextFieldDelegate {
    var onMicPressed: (() -> Void)?
    var onClearPressed: (() -> Void)?
    var onSettingsPressed: ((NSView) -> Void)?

    private var items: [TranscriptionHistoryItem] = []
    private var filteredItems: [TranscriptionHistoryItem] = []
    private var isRecording = false

    private let contentView = ThemeAwareView()
    private let searchField = NSTextField()
    private let searchPill = NSView()
    private let scrollView = NSScrollView()
    private let cardsStack = NSStackView()
    private let recordButton = CircleRecordButton()
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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceTyper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Palette.windowBackground
        window.minSize = NSSize(width: 400, height: 520)
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
    }

    func appendTranscription(_ text: String, createdAt: Date = Date()) {
        items.insert(TranscriptionHistoryItem(text: text, createdAt: createdAt), at: 0)
        saveHistory()
        applyFilter()
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
                self?.cardsStack.removeArrangedSubview(view)
                view.removeFromSuperview()
                if self?.filteredItems.isEmpty == true {
                    self?.emptyStateStack.isHidden = false
                }
            })
        } else {
            applyFilter()
        }
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        recordButton.setRecording(recording)
    }

    func clearHistory() {
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

    // MARK: - Layout Setup

    private func setupContent() {
        guard let window else { return }

        contentView.wantsLayer = true
        contentView.onAppearanceChanged = { [weak self] in
            self?.refreshColors()
        }
        window.contentView = contentView

        setupSearchField()
        setupBottomBar()
        setupScrollView()
        refreshColors()
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
            searchPill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 60),
            searchPill.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchPill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            searchPill.heightAnchor.constraint(equalToConstant: 36),

            searchField.leadingAnchor.constraint(equalTo: searchPill.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: searchPill.trailingAnchor, constant: -16),
            searchField.centerYAnchor.constraint(equalTo: searchPill.centerYAnchor),
        ])
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
        cardsStack.spacing = 16
        cardsStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(cardsStack)
        scrollView.documentView = documentView

        emptyStateStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(emptyStateStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: searchPill.bottomAnchor, constant: 16),
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
        renderCards()
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
        }
    }

    private func renderCards() {
        cardsStack.arrangedSubviews.forEach { view in
            cardsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        emptyStateStack.isHidden = !filteredItems.isEmpty

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
                card.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
            ])
        }
    }

    @objc private func recordButtonPressed() {
        onMicPressed?()
    }

    @objc private func clearButtonPressed() {
        clearHistory()
    }

    @objc private func settingsButtonPressed() {
        onSettingsPressed?(settingsButton)
    }
}

// MARK: - TranscriptionCardView

private final class TranscriptionCardView: NSView {
    override var isFlipped: Bool { true }
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

private final class IconButton: NSButton {
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

    private func refreshColors() {
        contentTintColor = Palette.secondaryText
    }
}

// MARK: - CircleRecordButton

private final class CircleRecordButton: NSButton {
    private var recording = false
    private let coralColor = NSColor(red: 253 / 255.0, green: 121 / 255.0, blue: 121 / 255.0, alpha: 1.0)

    private let pillView = NSView()
    private let micImageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Right Shift and hold to record")

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

    func setRecording(_ value: Bool) {
        recording = value
        statusLabel.stringValue = recording ? "Recording..." : "Right Shift and hold to record"
        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func refreshColors() {
        guard let layer = pillView.layer else { return }

        if recording {
            layer.backgroundColor = coralColor.withAlphaComponent(0.85).cgColor

            let pulse = CABasicAnimation(keyPath: "backgroundColor")
            pulse.fromValue = coralColor.withAlphaComponent(0.95).cgColor
            pulse.toValue = coralColor.withAlphaComponent(0.35).cgColor
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "recordingPulse")
        } else {
            layer.removeAnimation(forKey: "recordingPulse")
            layer.backgroundColor = coralColor.withAlphaComponent(0.85).cgColor
        }
    }
}

// MARK: - ThemeAwareView

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private class ThemeAwareView: NSView {
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

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestMatch == .darkAqua ? dark : light
        }
    }
}
