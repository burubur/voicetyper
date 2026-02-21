import ApplicationServices
import Cocoa

/// A simple view that catches mouse down events
private class ClickableContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

/// A floating visual overlay that appears while recording to signify VoiceTyper is active.
@MainActor
final class FloatingRecordingIndicator {
    static let shared = FloatingRecordingIndicator()
    var onAbort: (() -> Void)?

    private var window: NSWindow?
    private var circleLayer: CALayer?
    private let bgColor = NSColor(
        red: 253 / 255.0, green: 121 / 255.0, blue: 121 / 255.0, alpha: 1.0)

    private init() {}

    func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
                styleMask: .borderless,
                backing: .buffered,
                defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating  // Stays on top of everything
            win.ignoresMouseEvents = false
            win.hasShadow = false

            // Create a minimal recording circle
            let container = ClickableContainerView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            container.wantsLayer = true
            container.onMouseDown = { [weak self] in
                self?.onAbort?()
            }

            let circle = NSView(frame: NSRect(x: 2, y: 2, width: 28, height: 28))
            circle.wantsLayer = true
            self.circleLayer = circle.layer

            circle.layer?.backgroundColor = bgColor.withAlphaComponent(0.6).cgColor
            circle.layer?.cornerRadius = 14
            circle.layer?.borderWidth = 1.5
            circle.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor

            // Add shadow
            circle.layer?.shadowColor = NSColor.black.cgColor
            circle.layer?.shadowOpacity = 0.4
            circle.layer?.shadowOffset = CGSize(width: 0, height: -2)
            circle.layer?.shadowRadius = 3

            // Native macOS SF Symbol (much cleaner than the emoji)
            let micImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            let imageView = NSImageView(frame: NSRect(x: 7, y: 6, width: 14, height: 16))
            imageView.image = micImage
            imageView.contentTintColor = .white
            imageView.imageScaling = .scaleProportionallyUpOrDown

            circle.addSubview(imageView)
            container.addSubview(circle)
            win.contentView = container
            self.window = win
        }

        let position = getIndicatorPosition()
        window?.setFrameOrigin(position)
        window?.makeKeyAndOrderFront(nil)

        // Pop-in animation
        window?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window?.animator().alphaValue = 1.0
        }

        // Add pulsing recording animation to the background color
        let pulse = CABasicAnimation(keyPath: "backgroundColor")
        pulse.fromValue = bgColor.withAlphaComponent(0.8).cgColor
        pulse.toValue = bgColor.withAlphaComponent(0.3).cgColor
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        circleLayer?.add(pulse, forKey: "recordingPulse")
    }

    func hide() {
        guard let window = self.window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0.0
        } completionHandler: {
            DispatchQueue.main.async {
                window.orderOut(nil)
                self.circleLayer?.removeAnimation(forKey: "recordingPulse")
            }
        }
    }

    /// Places the indicator at the bottom center of the active screen.
    private func getIndicatorPosition() -> NSPoint {
        // `NSScreen.main` returns the screen with keyboard focus,
        // or the screen where the mouse is if no window is focused.
        let screen = NSScreen.main ?? NSScreen.screens.first!

        // visibleFrame accounts for the Dock and Menu bar
        let screenFrame = screen.visibleFrame

        let indicatorWidth: CGFloat = 32.0  // Matches the window width from show()
        let paddingBottom: CGFloat = 40.0  // Sensible padding from the bottom

        let x = screenFrame.midX - (indicatorWidth / 2.0)
        let y = screenFrame.minY + paddingBottom

        return NSPoint(x: x, y: y)
    }
}
