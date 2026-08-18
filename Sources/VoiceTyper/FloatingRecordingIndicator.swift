import ApplicationServices
import Cocoa

/// A clickable container view that catches mouse clicks to stop or discard recording
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

/// Floating, Blinking Recording Capsule Indicator.
///
/// Features:
/// - **Direct Dictation (.standard)**: Vibrant Coral/Rose pill with breathing white microphone icon.
/// - **Conversation Capture (.memoryVault)**: Vibrant Purple pill with breathing white microphone icon + Lap Counter (`01`) + Time Lapse (`04:28`).
/// - **Identical Height**: 34px (Corner radius 17px) across both modes.
@MainActor
final class FloatingRecordingIndicator {
    static let shared = FloatingRecordingIndicator()
    var onAbort: (() -> Void)?

    private var window: NSWindow?
    private var pillView: NSView?
    private var micIconView: NSImageView?
    private var lapLabel: NSTextField?
    private var timeLabel: NSTextField?
    private var separatorView: NSView?

    private var timer: Timer?
    private var startTime: Date?
    private var currentLap: Int = 1
    private var activeMode: DictationMode = .standard

    /// Vibrant coral/pink for direct dictation
    private let transcriptionCoral = NSColor(red: 255 / 255.0, green: 75 / 255.0, blue: 95 / 255.0, alpha: 0.95)
    /// Vibrant purple for conversation mode
    private let conversationPurple = NSColor(red: 168 / 255.0, green: 85 / 255.0, blue: 247 / 255.0, alpha: 0.95)

    private init() {}

    func show(mode: DictationMode = .standard, lap: Int = 1) {
        self.activeMode = mode
        self.currentLap = lap
        self.startTime = Date()

        let isMemo = (mode == .memoryVault)
        let winWidth: CGFloat = isMemo ? 116.0 : 42.0
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
            win.level = .floating
            win.ignoresMouseEvents = false
            win.hasShadow = false

            let container = ClickableContainerView(frame: win.contentView?.bounds ?? .zero)
            container.wantsLayer = true
            container.onMouseDown = { [weak self] in
                self?.onAbort?()
            }
            win.contentView = container
            self.window = win
        }

        buildPillUI(isMemo: isMemo, width: winWidth, height: winHeight)

        let position = getIndicatorPosition(width: winWidth)
        window?.setFrame(NSRect(origin: position, size: NSSize(width: winWidth, height: winHeight)), display: true)
        window?.makeKeyAndOrderFront(nil)

        // Smooth pop-in animation
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window?.animator().alphaValue = 1.0
        }

        startBlinkingAnimation()

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
                self?.micIconView?.layer?.removeAnimation(forKey: "micBlink")
                self?.pillView?.layer?.removeAnimation(forKey: "pillGlow")
            }
        }
    }

    // MARK: - UI Construction

    private func buildPillUI(isMemo: Bool, width: CGFloat, height: CGFloat) {
        guard let container = window?.contentView as? ClickableContainerView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        let pillColor = isMemo ? conversationPurple : transcriptionCoral

        let pill = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = height / 2.0
        pill.layer?.backgroundColor = pillColor.cgColor
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        pill.layer?.borderWidth = 1.0

        pill.layer?.shadowColor = pillColor.cgColor
        pill.layer?.shadowOpacity = 0.45
        pill.layer?.shadowOffset = CGSize(width: 0, height: -2)
        pill.layer?.shadowRadius = 8
        self.pillView = pill

        // 1. Crisp White Microphone Icon (on left)
        let micIcon = NSImageView(frame: NSRect(x: isMemo ? 10 : 12, y: 8, width: 18, height: 18))
        micIcon.wantsLayer = true
        micIcon.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording Microphone")
        micIcon.contentTintColor = .white
        micIcon.imageScaling = .scaleProportionallyUpOrDown
        self.micIconView = micIcon
        pill.addSubview(micIcon)

        if isMemo {
            // 2. Lap Counter in Middle (e.g. 01, 02)
            let lap = NSTextField(labelWithString: String(format: "%02d", currentLap))
            lap.frame = NSRect(x: 32, y: 8, width: 22, height: 18)
            lap.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            lap.textColor = .white
            lap.alignment = .center
            self.lapLabel = lap
            pill.addSubview(lap)

            // 3. Subtle 1px White Divider
            let sep = NSBox(frame: NSRect(x: 58, y: 9, width: 1, height: 16))
            sep.boxType = .custom
            sep.fillColor = NSColor.white.withAlphaComponent(0.4)
            sep.borderWidth = 0
            self.separatorView = sep
            pill.addSubview(sep)

            // 4. Live Ticking Time Lapse (00:00)
            let time = NSTextField(labelWithString: "00:00")
            time.frame = NSRect(x: 64, y: 8, width: 44, height: 18)
            time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            time.textColor = .white
            time.alignment = .center
            self.timeLabel = time
            pill.addSubview(time)
        }

        container.addSubview(pill)
    }

    private func startBlinkingAnimation() {
        // Microphone breathing opacity & scale animation
        micIconView?.layer?.removeAnimation(forKey: "micBlink")
        pillView?.layer?.removeAnimation(forKey: "pillGlow")

        let blinkGroup = CAAnimationGroup()
        blinkGroup.duration = 0.85
        blinkGroup.autoreverses = true
        blinkGroup.repeatCount = .infinity
        blinkGroup.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.4

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.18

        blinkGroup.animations = [opacity, scale]
        micIconView?.layer?.add(blinkGroup, forKey: "micBlink")

        // Subtle outer pill glow pulse
        let glowPulse = CABasicAnimation(keyPath: "shadowOpacity")
        glowPulse.duration = 0.85
        glowPulse.autoreverses = true
        glowPulse.repeatCount = .infinity
        glowPulse.fromValue = 0.45
        glowPulse.toValue = 0.75
        glowPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pillView?.layer?.add(glowPulse, forKey: "pillGlow")
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

    // MARK: - Positioning

    private func getIndicatorPosition(width: CGFloat) -> NSPoint {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let paddingBottom: CGFloat = 40.0
        let x = screenFrame.midX - (width / 2.0)
        let y = screenFrame.minY + paddingBottom

        return NSPoint(x: x, y: y)
    }
}
