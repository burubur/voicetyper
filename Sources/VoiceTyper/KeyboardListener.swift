import Cocoa
import Foundation

// MARK: - DictationMode

/// Represents the operating mode for the dictation recording session.
public enum DictationMode: Sendable, Equatable {
    /// Standard dictation (Right Option alone) -> Hold-to-talk, transcribes and injects text into active window.
    case standard

    /// Voice conversation memo (Shift + Right Option) -> Hands-free toggle, transcribes and archives raw audio WAV + text in ~/.voicetyper/conversation.
    case memoryVault
}

// MARK: - KeyboardListenerDelegate

/// Callbacks from the dictation state machine.
@MainActor
protocol KeyboardListenerDelegate: AnyObject, Sendable {
    func keyboardListenerDidStartRecording(mode: DictationMode)
    func keyboardListenerDidStopRecording(mode: DictationMode)
    func keyboardListenerDidAbort()
}

// MARK: - KeyboardListener

/// Monitors global keyboard events via CGEvent tap.
///
/// Implements:
/// - **Direct Dictation (`Right Option`)**: Hold-to-Talk (quick 3-10s inline typing).
/// - **Conversation Capture (`Shift + Right Option`)**: Hands-Free Toggle (1st tap starts, 2nd tap stops).
/// - **Grace Period**: 800ms window after release in hold-to-talk mode to resume mid-sentence.
/// - **Double-Tap Abort**: Rapid double-tap on Right Option aborts dictation.
final class KeyboardListener: @unchecked Sendable {
    weak var delegate: KeyboardListenerDelegate?

    private var isKeyPressed = false
    private var isRecording = false
    private var isHandsFreeActive = false
    private var activeMode: DictationMode = .standard
    private var lastPressTime: TimeInterval = 0
    private var lastReleaseTime: TimeInterval = 0
    private var handsFreeStartTime: TimeInterval = 0
    private let gracePeriodSeconds: TimeInterval = 0.8

    private var graceTimer: DispatchSourceTimer?
    private var eventTap: CFMachPort?

    /// The modifier flag for Right Option key (keyCode 0x3D = 61).
    private let rightOptionKeyCode: UInt16 = 0x3D

    /// Physical Right Option device bitmask in CGEvent raw flags (0x40 / NX_DEVICERALTKEYMASK).
    private let nxDeviceRightOptionMask: UInt64 = 0x00000040

    /// The key code for the 'C' key.
    private let cKeyCode: UInt16 = 0x08

    /// Installs a global CGEvent tap to monitor key events.
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
        print("⌨️  Key listener active: Right Option to Dictate | Shift + Right Option for Hands-Free Memo.")
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
            isHandsFreeActive = false
            Task { @MainActor in delegate?.keyboardListenerDidAbort() }
            return Unmanaged.passRetained(event)
        }
        return Unmanaged.passRetained(event)
    }

    private func handleFlagsChanged(event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Only respond to Right Option key (keyCode 0x3D = 61)
        guard keyCode == rightOptionKeyCode else { return }

        let isOptionDown = event.flags.contains(.maskAlternate) || (event.flags.rawValue & nxDeviceRightOptionMask) != 0

        if isOptionDown {
            if !isKeyPressed {
                isKeyPressed = true
                let isShiftDown = event.flags.contains(.maskShift)
                let mode: DictationMode = isShiftDown ? .memoryVault : .standard

                if mode == .memoryVault {
                    let now = ProcessInfo.processInfo.systemUptime
                    if isHandsFreeActive {
                        // 2nd tap on Shift+Option -> Stop hands-free capture (with 350ms debounce)
                        if (now - handsFreeStartTime) >= 0.35 {
                            print("⏹️ 2nd tap detected on Shift+Option: Stopping hands-free capture...")
                            isHandsFreeActive = false
                            isRecording = false
                            cancelGraceTimer()
                            Task { @MainActor in delegate?.keyboardListenerDidStopRecording(mode: .memoryVault) }
                        }
                    } else {
                        // 1st tap on Shift+Option -> Start hands-free capture
                        print("🎙️ 1st tap detected on Shift+Option: Starting hands-free capture...")
                        isHandsFreeActive = true
                        isRecording = true
                        self.activeMode = .memoryVault
                        handsFreeStartTime = now
                        lastPressTime = now
                        cancelGraceTimer()
                        Task { @MainActor in delegate?.keyboardListenerDidStartRecording(mode: .memoryVault) }
                    }
                } else {
                    // Standard Direct Dictation: Hold-to-Talk
                    if isHandsFreeActive {
                        // While in hands-free capture, ignore accidental Option presses
                        return
                    }
                    handleKeyDown(mode: .standard)
                }
            }
        } else {
            if isKeyPressed {
                isKeyPressed = false
                if isHandsFreeActive {
                    // In hands-free mode, releasing keys does NOT stop recording!
                    return
                }
                handleKeyUp()
            }
        }
    }

    private func handleKeyDown(mode: DictationMode) {
        let now = ProcessInfo.processInfo.systemUptime
        let timeSinceLastRelease = now - lastReleaseTime
        let timeSinceLastPress = now - lastPressTime

        lastPressTime = now
        self.activeMode = mode

        // Double-tap abort: if user taps Right Option twice rapidly (< 300ms since release)
        if isRecording, timeSinceLastRelease < 0.3, timeSinceLastPress < 0.6 {
            print("🛑 Double-tap detected! Aborting dictation...")
            cancelGraceTimer()
            isRecording = false
            isHandsFreeActive = false
            Task { @MainActor in delegate?.keyboardListenerDidAbort() }
            return
        }

        if !isRecording {
            isRecording = true
            let recordingMode = self.activeMode
            Task { @MainActor in delegate?.keyboardListenerDidStartRecording(mode: recordingMode) }
        } else {
            // Resumed within grace period — cancel the pending stop
            cancelGraceTimer()
        }
    }

    private func handleKeyUp() {
        lastReleaseTime = ProcessInfo.processInfo.systemUptime
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

        guard !isKeyPressed, isRecording, !isHandsFreeActive else { return }

        isRecording = false
        let finishedMode = self.activeMode
        Task { @MainActor in delegate?.keyboardListenerDidStopRecording(mode: finishedMode) }
    }

    // MARK: - API

    /// Forces an abort sequence externally (e.g., from a UI click)
    func forceAbort() {
        print("🛑 Force abort triggered externally!")
        cancelGraceTimer()
        isRecording = false
        isKeyPressed = false
        isHandsFreeActive = false
        Task { @MainActor in delegate?.keyboardListenerDidAbort() }
    }
}
