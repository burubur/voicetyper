import Cocoa
import Foundation

// MARK: - KeyboardListenerDelegate

/// Callbacks from the hold-to-talk state machine.
@MainActor
protocol KeyboardListenerDelegate: AnyObject, Sendable {
    func keyboardListenerDidStartRecording()
    func keyboardListenerDidStopRecording()
    func keyboardListenerDidAbort()
}

// MARK: - KeyboardListener

/// Monitors global keyboard events via CGEvent tap.
///
/// Implements a hold-to-talk state machine with:
/// - **Hold-to-Record**: Hold Right Shift to record, release to process.
/// - **Grace Period**: 400ms window after release to resume recording
///   (allows brief pauses mid-sentence without chopping audio).
/// - **Double-Tap Abort**: Two rapid presses within 400ms aborts the
///   current recording and discards audio.
final class KeyboardListener: @unchecked Sendable {
    weak var delegate: KeyboardListenerDelegate?

    private var isKeyPressed = false
    private var isRecording = false
    private var lastPressTime: TimeInterval = 0
    private var lastReleaseTime: TimeInterval = 0
    private let gracePeriodSeconds: TimeInterval = 0.8

    private var graceTimer: DispatchSourceTimer?

    /// The modifier flag for Right Shift key.
    /// CGEvent reports Right Shift as `.maskShift` combined with keyCode check.
    /// We use flagsChanged event and check the raw keyCode for right shift (0x3C).
    private let rightShiftKeyCode: UInt16 = 0x3C

    /// The key code for the 'C' key.
    private let cKeyCode: UInt16 = 0x08

    /// Installs a global CGEvent tap to monitor key events.
    /// Requires Accessibility permissions.
    func start() {
        let eventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else {
                        return Unmanaged.passRetained(event)
                    }
                    let listener = Unmanaged<KeyboardListener>.fromOpaque(refcon)
                        .takeUnretainedValue()

                    if type == .flagsChanged {
                        listener.handleFlagsChanged(event: event)
                        return Unmanaged.passRetained(event)
                    } else if type == .keyDown {
                        return listener.handleKeyDownEvent(event: event)
                    }

                    return Unmanaged.passRetained(event)
                },
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
        else {
            print("❌ Failed to create event tap. Grant Accessibility permissions in:")
            print("   System Settings > Privacy & Security > Accessibility")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        print("⌨️  Key listener active. Hold 'Right Shift' to dictate.")
    }

    // MARK: - Event Handling

    private func handleKeyDownEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check for Ctrl + C
        if keyCode == cKeyCode && flags.contains(.maskControl) {
            print("🛑 Ctrl+C explicitly pressed! Aborting any ongoing Dictation...")
            cancelGraceTimer()
            isRecording = false
            Task { @MainActor in delegate?.keyboardListenerDidAbort() }
            return Unmanaged.passRetained(event)
        }
        return Unmanaged.passRetained(event)
    }

    private func handleFlagsChanged(event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Only respond to Right Shift key
        guard keyCode == rightShiftKeyCode else { return }

        let isShiftDown = event.flags.contains(.maskShift)

        if isShiftDown {
            handleKeyDown()
        } else {
            handleKeyUp()
        }
    }

    private func handleKeyDown() {
        let now = ProcessInfo.processInfo.systemUptime

        lastPressTime = now
        isKeyPressed = true

        if !isRecording {
            // Fresh start
            isRecording = true
            Task { @MainActor in delegate?.keyboardListenerDidStartRecording() }
        } else {
            // Resumed within grace period — cancel the pending stop
            cancelGraceTimer()
        }
    }

    private func handleKeyUp() {
        guard isKeyPressed else { return }
        isKeyPressed = false
        lastReleaseTime = ProcessInfo.processInfo.systemUptime

        let holdDuration = lastReleaseTime - lastPressTime

        // If the user tapped the key quickly (under 250ms), we consider it an abort.
        // This handles "Double Tap Abort" because the second press of a double-tap
        // will have a very short hold duration. It also catches accidental single taps.
        if holdDuration < 0.25, isRecording {
            print("🛑 Quick tap detected! Aborting recording...")
            cancelGraceTimer()
            isRecording = false
            Task { @MainActor in delegate?.keyboardListenerDidAbort() }
            return
        }

        // Start grace period timer
        startGraceTimer()
    }

    // MARK: - Grace Period Timer

    private func startGraceTimer() {
        cancelGraceTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + gracePeriodSeconds)
        timer.setEventHandler { [weak self] in
            self?.graceTimerFired()
        }
        timer.resume()
        graceTimer = timer
    }

    private func cancelGraceTimer() {
        graceTimer?.cancel()
        graceTimer = nil
    }

    private func graceTimerFired() {
        graceTimer = nil

        // Only finalize if key is still released (not re-pressed during grace period)
        guard !isKeyPressed, isRecording else { return }

        isRecording = false
        Task { @MainActor in delegate?.keyboardListenerDidStopRecording() }
    }

    // MARK: - API

    /// Forces an abort sequence externally (e.g., from a UI click)
    func forceAbort() {
        print("🛑 Force abort triggered externally!")
        cancelGraceTimer()
        isRecording = false
        isKeyPressed = false
        Task { @MainActor in delegate?.keyboardListenerDidAbort() }
    }
}
