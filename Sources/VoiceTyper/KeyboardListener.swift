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
/// - **Hold-to-Record**: Hold Right Option to record, release to process.
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
    private var eventTap: CFMachPort?

    /// The modifier flag for Right Option key.
    /// CGEvent reports Right Option as `.maskAlternate` combined with keyCode check.
    /// We use flagsChanged event and check the raw keyCode for right option (0x3D).
    private let rightOptionKeyCode: UInt16 = 0x3D

    /// Physical Right Option device bitmask in CGEvent raw flags (0x40 / NX_DEVICERALTKEYMASK / NX_DEVICEROPTIONKEYMASK).
    private let nxDeviceRightOptionMask: UInt64 = 0x00000040

    /// The key code for the 'C' key.
    private let cKeyCode: UInt16 = 0x08

    /// Installs a global CGEvent tap to monitor key events.
    /// Requires Accessibility permissions.
    func start() {
        let eventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
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

                    // Handle tap disabled by timeout/user input recovery
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let eventTap = listener.eventTap {
                            CGEvent.tapEnable(tap: eventTap, enable: true)
                        }
                        return Unmanaged.passRetained(event)
                    }

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
            Task { @MainActor in
                self.showAccessibilityAlert()
            }
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("⌨️  Key listener active. Right Option and hold to record.")
    }

    @MainActor
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "VoiceTyper needs Accessibility permission to detect the Right Option key for dictation.\n\nPlease grant Accessibility access in System Settings > Privacy & Security > Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
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

        // Only respond to Right Option key (keyCode 0x3D = 61)
        guard keyCode == rightOptionKeyCode else { return }

        // Check if Right Option is pressed down.
        // CGEventFlags.maskAlternate indicates Option modifier state.
        // We also check (event.flags.rawValue & nxDeviceRightOptionMask) != 0 for hardware mask compatibility.
        let isOptionDown = event.flags.contains(.maskAlternate) || (event.flags.rawValue & nxDeviceRightOptionMask) != 0

        if isOptionDown {
            if !isKeyPressed {
                handleKeyDown()
            }
        } else {
            if isKeyPressed {
                handleKeyUp()
            }
        }
    }

    private func handleKeyDown() {
        let now = ProcessInfo.processInfo.systemUptime
        let timeSinceLastRelease = now - lastReleaseTime
        let timeSinceLastPress = now - lastPressTime

        lastPressTime = now
        isKeyPressed = true

        // Double-tap abort: if user taps Right Option twice rapidly (< 300ms since release)
        if isRecording, timeSinceLastRelease < 0.3, timeSinceLastPress < 0.6 {
            print("🛑 Double-tap detected! Aborting dictation...")
            cancelGraceTimer()
            isRecording = false
            Task { @MainActor in delegate?.keyboardListenerDidAbort() }
            return
        }

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

        // Start grace period timer to finalize recording
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
