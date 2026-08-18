import ApplicationServices
import Cocoa

/// A simple view that catches mouse down events
private class ClickableContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

/// A minimalist floating visual overlay that appears while recording.
///
/// Supports:
/// - **Direct Dictation (.standard)**: Compact 32x32 pulsing coral circle.
/// - **Conversation Capture (.memoryVault)**: Sleek minimal ~90x28px pill with pulsing purple dot, lap badge (`01`, `02`), and ticking timer (`04:28`).
@MainActor
final class FloatingRecordingIndicator {
    static let shared = FloatingRecordingIndicator()
    var onAbort: (() -> Void)?

    private var window: NSWindow?
    private var pillView: NSView?
    private var dotLayer: CALayer?
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
        let winWidth: CGFloat = isMemo ? 92.0 : 32.0
        let winHeight: CGFloat = isMemo ? 28.0 : 32.0

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

        // Pop-in animation
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window?.animator().alphaValue = 1.0
        }

        startPulsing(isMemo: isMemo)

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
                self?.dotLayer?.removeAnimation(forKey: "recordingPulse")
            }
        }
    }

    // MARK: - UI Construction

    private func buildPillUI(isMemo: Bool, width: CGFloat, height: CGFloat) {
        guard let container = window?.contentView as? ClickableContainerView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        let pill = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = height / 2.0
        pill.layer?.borderWidth = 1.2
        pill.layer?.borderColor = isMemo ? memoryPurple.withAlphaComponent(0.6).cgColor : NSColor.white.withAlphaComponent(0.5).cgColor
        pill.layer?.backgroundColor = isMemo ? NSColor.black.withAlphaComponent(0.75).cgColor : standardCoral.withAlphaComponent(0.85).cgColor

        pill.layer?.shadowColor = NSColor.black.cgColor
        pill.layer?.shadowOpacity = 0.35
        pill.layer?.shadowOffset = CGSize(width: 0, height: -2)
        pill.layer?.shadowRadius = 4
        self.pillView = pill

        if isMemo {
            // Purple pulsing dot
            let dot = NSView(frame: NSRect(x: 8, y: 9, width: 10, height: 10))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 5
            dot.layer?.backgroundColor = memoryPurple.cgColor
            self.dotLayer = dot.layer
            pill.addSubview(dot)

            // Minimal Lap Number (e.g. 01, 02)
            let lap = NSTextField(labelWithString: String(format: "%02d", currentLap))
            lap.frame = NSRect(x: 21, y: 5, width: 18, height: 18)
            lap.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
            lap.textColor = memoryPurple
            lap.alignment = .left
            self.lapLabel = lap
            pill.addSubview(lap)

            // 1px Subtle Separator
            let sep = NSBox(frame: NSRect(x: 42, y: 7, width: 1, height: 14))
            sep.boxType = .custom
            sep.fillColor = NSColor.white.withAlphaComponent(0.25)
            sep.borderWidth = 0
            self.separatorView = sep
            pill.addSubview(sep)

            // Minimal Ticking Timer (00:00)
            let time = NSTextField(labelWithString: "00:00")
            time.frame = NSRect(x: 46, y: 5, width: 40, height: 18)
            time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            time.textColor = .white
            time.alignment = .center
            self.timeLabel = time
            pill.addSubview(time)
        } else {
            // Direct dictation: Simple 32x32 mic icon
            let dot = NSView(frame: NSRect(x: 2, y: 2, width: 28, height: 28))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 14
            dot.layer?.backgroundColor = standardCoral.withAlphaComponent(0.85).cgColor
            self.dotLayer = dot.layer

            let imgView = NSImageView(frame: NSRect(x: 7, y: 6, width: 14, height: 16))
            imgView.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            imgView.contentTintColor = .white
            imgView.imageScaling = .scaleProportionallyUpOrDown
            dot.addSubview(imgView)
            pill.addSubview(dot)
        }

        container.addSubview(pill)
    }

    private func startPulsing(isMemo: Bool) {
        dotLayer?.removeAnimation(forKey: "recordingPulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer?.add(pulse, forKey: "recordingPulse")
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
