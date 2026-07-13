import Cocoa

// MARK: - TranscriptionHistoryItem

struct TranscriptionHistoryItem {
    let text: String
    let createdAt: Date
}

// MARK: - TranscriptionHistoryWindowController

@MainActor
final class TranscriptionHistoryWindowController: NSWindowController, NSSearchFieldDelegate {
    var onMicPressed: (() -> Void)?
    var onClearPressed: (() -> Void)?
    var onSettingsPressed: (() -> Void)?

    private var items: [TranscriptionHistoryItem] = []
    private var filteredItems: [TranscriptionHistoryItem] = []
    private var isRecording = false

    private let contentView = ThemeAwareView()
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let cardsStack = NSStackView()
    private let recordButton = CircleRecordButton()
    private let emptyLabel = NSTextField(labelWithString: "No transcriptions yet")
    private let bottomBar = ThemeAwareView()

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
        applyFilter()
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        recordButton.setRecording(recording)
    }

    func clearHistory() {
        items.removeAll()
        applyFilter()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    private func setupContent() {
        guard let window else { return }

        contentView.wantsLayer = true
        contentView.onAppearanceChanged = { [weak self] in
            self?.refreshColors()
        }
        window.contentView = contentView

        setupSearchField()
        setupScrollView()
        setupBottomBar()
        refreshColors()
    }

    private func setupSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.placeholderString = "Search in transcriptions"
        searchField.font = .systemFont(ofSize: 15, weight: .regular)
        searchField.textColor = Palette.primaryText
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 24
        searchField.layer?.borderWidth = 1
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel

        contentView.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 72),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            searchField.heightAnchor.constraint(equalToConstant: 40),
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
        cardsStack.spacing = 20
        cardsStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(cardsStack)
        scrollView.documentView = documentView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        emptyLabel.textColor = Palette.secondaryText
        emptyLabel.alignment = .center

        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 22),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -178),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.topAnchor.constraint(equalTo: cardsStack.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: cardsStack.bottomAnchor),
            documentView.leadingAnchor.constraint(equalTo: cardsStack.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: cardsStack.trailingAnchor),

            cardsStack.widthAnchor.constraint(equalTo: documentView.widthAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.wantsLayer = true
        contentView.addSubview(bottomBar)

        let shortcutIcon = NSTextField(labelWithString: "⇧")
        shortcutIcon.translatesAutoresizingMaskIntoConstraints = false
        shortcutIcon.font = .systemFont(ofSize: 16, weight: .medium)
        shortcutIcon.textColor = Palette.secondaryText

        let shortcutLabel = NSTextField(labelWithString: "Right Shift to record")
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .regular)
        shortcutLabel.textColor = Palette.secondaryText

        let dropImage = NSImageView(image: NSImage(systemSymbolName: "doc.badge.arrow.down", accessibilityDescription: nil) ?? NSImage())
        dropImage.translatesAutoresizingMaskIntoConstraints = false
        dropImage.contentTintColor = Palette.secondaryText
        dropImage.imageScaling = .scaleProportionallyUpOrDown

        let dropLabel = NSTextField(labelWithString: "Drop audio file here to transcribe")
        dropLabel.translatesAutoresizingMaskIntoConstraints = false
        dropLabel.font = .systemFont(ofSize: 13, weight: .regular)
        dropLabel.textColor = Palette.secondaryText

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.target = self
        recordButton.action = #selector(recordButtonPressed)

        let micButton = iconButton(symbol: "mic.fill", action: #selector(recordButtonPressed))
        let clearButton = iconButton(symbol: "trash", action: #selector(clearButtonPressed))
        let settingsButton = iconButton(symbol: "gearshape", action: #selector(settingsButtonPressed))

        bottomBar.addSubview(recordButton)
        bottomBar.addSubview(shortcutIcon)
        bottomBar.addSubview(shortcutLabel)
        bottomBar.addSubview(dropImage)
        bottomBar.addSubview(dropLabel)
        bottomBar.addSubview(micButton)
        bottomBar.addSubview(clearButton)
        bottomBar.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 170),

            recordButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            recordButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 42),
            recordButton.widthAnchor.constraint(equalToConstant: 44),
            recordButton.heightAnchor.constraint(equalToConstant: 44),

            shortcutIcon.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 28),
            shortcutIcon.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -58),
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutIcon.trailingAnchor, constant: 12),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutIcon.centerYAnchor),

            dropImage.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 28),
            dropImage.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -26),
            dropImage.widthAnchor.constraint(equalToConstant: 18),
            dropImage.heightAnchor.constraint(equalToConstant: 22),
            dropLabel.leadingAnchor.constraint(equalTo: dropImage.trailingAnchor, constant: 12),
            dropLabel.centerYAnchor.constraint(equalTo: dropImage.centerYAnchor),

            micButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -12),
            clearButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -12),
            settingsButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),
            micButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -24),
            clearButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -24),
            settingsButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -24),
        ])
    }

    private func iconButton(symbol: String, action: Selector) -> IconButton {
        let button = IconButton(symbol: symbol)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
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
        searchField.layer?.backgroundColor = Palette.searchBackground.cgColor
        searchField.layer?.borderColor = Palette.border.cgColor
        emptyLabel.textColor = Palette.secondaryText
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

        emptyLabel.isHidden = !filteredItems.isEmpty

        for item in filteredItems {
            let card = TranscriptionCardView(
                text: item.text,
                date: dateFormatter.string(from: item.createdAt),
                time: timeFormatter.string(from: item.createdAt)
            )
            card.translatesAutoresizingMaskIntoConstraints = false
            cardsStack.addArrangedSubview(card)
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 124).isActive = true
        }
    }

    @objc private func recordButtonPressed() {
        onMicPressed?()
    }

    @objc private func clearButtonPressed() {
        clearHistory()
        onClearPressed?()
    }

    @objc private func settingsButtonPressed() {
        onSettingsPressed?()
    }
}

// MARK: - TranscriptionCardView

private final class TranscriptionCardView: NSView {
    private let textLabel: NSTextField
    private let dateLabel: NSTextField
    private let timeLabel: NSTextField

    init(text: String, date: String, time: String) {
        self.textLabel = NSTextField(wrappingLabelWithString: text)
        self.dateLabel = NSTextField(labelWithString: date)
        self.timeLabel = NSTextField(labelWithString: time)

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .systemFont(ofSize: 15, weight: .regular)
        textLabel.maximumNumberOfLines = 2
        textLabel.lineBreakMode = .byTruncatingTail

        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .separator
        divider.alphaValue = 0.5

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        addSubview(textLabel)
        addSubview(divider)
        addSubview(dateLabel)
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 26),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            divider.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 24),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            dateLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            timeLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            timeLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -18),
        ])

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
        imageScaling = .scaleNone
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
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
        layer?.backgroundColor = Palette.controlBackground.cgColor
        layer?.borderColor = Palette.border.cgColor
        contentTintColor = Palette.primaryText
    }
}

// MARK: - CircleRecordButton

private final class CircleRecordButton: NSButton {
    private var recording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        imagePosition = .noImage
        title = ""
        setRecording(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRecording(_ value: Bool) {
        recording = value
        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func refreshColors() {
        layer?.cornerRadius = 26
        layer?.backgroundColor = recording ? Palette.recording.cgColor : Palette.recordIdle.cgColor
        layer?.shadowColor = (recording ? Palette.recording : Palette.recordIdle).cgColor
        layer?.shadowOpacity = recording ? 0.85 : 0.45
        layer?.shadowRadius = recording ? 24 : 18
        layer?.shadowOffset = .zero
    }
}

// MARK: - ThemeAwareView

private final class ThemeAwareView: NSView {
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
    static let recording = NSColor(calibratedRed: 0.99, green: 0.38, blue: 0.36, alpha: 1)

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestMatch == .darkAqua ? dark : light
        }
    }
}
