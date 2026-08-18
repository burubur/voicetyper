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

/// A minimalist circular floating indicator that pulses in opacity while recording.
@MainActor
final class FloatingRecordingIndicator {
    static let shared = FloatingRecordingIndicator()
    var onAbort: (() -> Void)?

    private var window: NSWindow?
    private var circleLayer: CALayer?
    private var imageView: NSImageView?

    private let standardCoral = NSColor(red: 253 / 255.0, green: 121 / 255.0, blue: 121 / 255.0, alpha: 1.0)
    private let memoryPurple = NSColor(red: 168 / 255.0, green: 85 / 255.0, blue: 247 / 255.0, alpha: 1.0)

    private init() {}

    func show(mode: DictationMode = .standard, lap: Int = 1) {
        let activeBgColor = (mode == .memoryVault) ? memoryPurple : standardCoral
        let symbolName = "mic.fill"

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 34, height: 34),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating  // Stays on top of everything
            win.ignoresMouseEvents = false
            win.hasShadow = false

            // Create a minimal recording circle containing only the icon
            let container = ClickableContainerView(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
            container.wantsLayer = true
            container.onMouseDown = { [weak self] in
                self?.onAbort?()
            }

            let circle = NSView(frame: NSRect(x: 2, y: 2, width: 30, height: 30))
            circle.wantsLayer = true
            self.circleLayer = circle.layer

            circle.layer?.cornerRadius = 15
            circle.layer?.borderWidth = 1.5
            circle.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor

            // Add shadow
            circle.layer?.shadowColor = NSColor.black.cgColor
            circle.layer?.shadowOpacity = 0.35
            circle.layer?.shadowOffset = CGSize(width: 0, height: -2)
            circle.layer?.shadowRadius = 4

            let imgView = NSImageView(frame: NSRect(x: 7, y: 6, width: 16, height: 18))
            imgView.contentTintColor = .white
            imgView.imageScaling = .scaleProportionallyUpOrDown
            self.imageView = imgView

            circle.addSubview(imgView)
            container.addSubview(circle)
            win.contentView = container
            self.window = win
        }

        circleLayer?.backgroundColor = activeBgColor.withAlphaComponent(0.85).cgColor
        let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        imageView?.image = symbolImage

        let position = getIndicatorPosition()
        window?.setFrameOrigin(position)
        window?.makeKeyAndOrderFront(nil)

        // Pop-in animation
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window?.animator().alphaValue = 1.0
        }

        // Pure opacity pulse on background color (no icon resizing or shifting)
        circleLayer?.removeAnimation(forKey: "recordingPulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        circleLayer?.add(pulse, forKey: "recordingPulse")
    }

    func updateLap(_ lap: Int) {
        // Lap state tracked internally for conversation chunks
    }

    func hide() {
        guard let window = self.window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                window.orderOut(nil)
                self?.circleLayer?.removeAnimation(forKey: "recordingPulse")
            }
        }
    }

    /// Places the circular indicator at the bottom center of the active screen.
    private func getIndicatorPosition() -> NSPoint {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let indicatorWidth: CGFloat = 34.0
        let paddingBottom: CGFloat = 40.0

        let x = screenFrame.midX - (indicatorWidth / 2.0)
        let y = screenFrame.minY + paddingBottom

        return NSPoint(x: x, y: y)
    }
}
