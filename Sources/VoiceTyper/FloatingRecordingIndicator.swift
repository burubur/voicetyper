import ApplicationServices
import Cocoa

/// A simple view that catches mouse down events to cancel/discard recording
private class ClickableContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

/// Floating recording indicator:
/// - **Direct Transcription (.standard)**: 34x34px Pink/Coral Circle with centered breathing microphone icon.
/// - **Conversation Capture (.memoryVault)**: 116x34px Purple Pill with breathing microphone on left, Lap Counter (`01`), and live Time Lapse (`04:28`) on right.
@MainActor
final class FloatingRecordingIndicator {
    static let shared = FloatingRecordingIndicator()
    var onAbort: (() -> Void)?

    private var window: NSWindow?
    private var pillLayer: CALayer?
    private var imageView: NSImageView?
    private var lapLabel: NSTextField?
    private var timeLabel: NSTextField?
    private var separatorView: NSView?

    private var timer: Timer?
    private var startTime: Date?
    private var currentLap: Int = 1
    private var activeMode: DictationMode = .standard

    private let standardCoral = NSColor(red: 253 / 255.0, green: 121 / 255.0, blue: 121 / 255.0, alpha: 1.0)
    private let memoryPurple = NSColor(red: 168 / 255.0, green: 85 / 255.0, blue: 247 / 255.0, alpha: 1.0)

    private init() {}

    func show(mode: DictationMode = .standard, lap: Int = 1) {
        self.activeMode = mode
        self.currentLap = lap
        self.startTime = Date()

        let isMemo = (mode == .memoryVault)
        let activeBgColor = isMemo ? memoryPurple : standardCoral

        let winWidth: CGFloat = isMemo ? 116.0 : 34.0
        let winHeight: CGFloat = 34.0

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating  // Stays on top
            win.ignoresMouseEvents = false
            win.hasShadow = false

            let container = ClickableContainerView(frame: NSRect(x: 0, y: 0, width: winWidth, height: winHeight))
            container.wantsLayer = true
            container.onMouseDown = { [weak self] in
                self?.onAbort?()
            }
            win.contentView = container
            self.window = win
        }

        buildUI(isMemo: isMemo, width: winWidth, height: winHeight, color: activeBgColor)

        let position = getIndicatorPosition(width: winWidth)
        window?.setFrame(NSRect(origin: position, size: NSSize(width: winWidth, height: winHeight)), display: true)
        window?.makeKeyAndOrderFront(nil)

        // Smooth pop-in animation
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window?.animator().alphaValue = 1.0
        }

        // Pure opacity pulse on background color (no icon resizing or shifting)
        pillLayer?.removeAnimation(forKey: "recordingPulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pillLayer?.add(pulse, forKey: "recordingPulse")

        if isMemo {
            startTimer()
        } else {
            stopTimer()
        }
    }

    func updateLap(_ lap: Int) {
        self.currentLap = lap
        self.startTime = Date()
        lapLabel?.stringValue = String(format: "%02d", lap)
        timeLabel?.stringValue = "00:00"
    }

    func hide() {
        stopTimer()
        guard let window = self.window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                window.orderOut(nil)
                self?.pillLayer?.removeAnimation(forKey: "recordingPulse")
            }
        }
    }

    // MARK: - UI Construction

    private func buildUI(isMemo: Bool, width: CGFloat, height: CGFloat, color: NSColor) {
        guard let container = window?.contentView as? ClickableContainerView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        let pill = NSView(frame: NSRect(x: 2, y: 2, width: width - 4, height: height - 4))
        pill.wantsLayer = true
        self.pillLayer = pill.layer

        pill.layer?.cornerRadius = (height - 4) / 2.0
        pill.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        pill.layer?.borderWidth = 1.5
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor

        // Shadow
        pill.layer?.shadowColor = NSColor.black.cgColor
        pill.layer?.shadowOpacity = 0.35
        pill.layer?.shadowOffset = CGSize(width: 0, height: -2)
        pill.layer?.shadowRadius = 4

        // 1. Microphone Icon
        let micX: CGFloat = isMemo ? 8 : 7
        let imgView = NSImageView(frame: NSRect(x: micX, y: 6, width: 15, height: 18))
        imgView.contentTintColor = .white
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording Microphone")
        self.imageView = imgView
        pill.addSubview(imgView)

        if isMemo {
            // 2. Lap Counter (e.g. 01, 02)
            let lap = NSTextField(labelWithString: String(format: "%02d", currentLap))
            lap.frame = NSRect(x: 27, y: 6, width: 22, height: 18)
            lap.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            lap.textColor = .white
            lap.alignment = .center
            self.lapLabel = lap
            pill.addSubview(lap)

            // 3. Subtle 1px Divider
            let sep = NSBox(frame: NSRect(x: 52, y: 8, width: 1, height: 14))
            sep.boxType = .custom
            sep.fillColor = NSColor.white.withAlphaComponent(0.35)
            sep.borderWidth = 0
            self.separatorView = sep
            pill.addSubview(sep)

            // 4. Live Ticking Time Lapse (00:00) exactly after lap counter
            let time = NSTextField(labelWithString: "00:00")
            time.frame = NSRect(x: 58, y: 6, width: 46, height: 18)
            time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            time.textColor = .white
            time.alignment = .center
            self.timeLabel = time
            pill.addSubview(time)
        }

        container.addSubview(pill)
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimerLabel()
            }
        }
        updateTimerLabel()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTimerLabel() {
        guard let startTime = startTime else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        timeLabel?.stringValue = String(format: "%02d:%02d", minutes, seconds)
    }

    /// Places the indicator at the bottom center of the active screen.
    private func getIndicatorPosition(width: CGFloat) -> NSPoint {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let paddingBottom: CGFloat = 40.0

        let x = screenFrame.midX - (width / 2.0)
        let y = screenFrame.minY + paddingBottom

        return NSPoint(x: x, y: y)
    }
}
