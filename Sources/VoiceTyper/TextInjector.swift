import Cocoa
import Foundation

// MARK: - TextInjector

/// Injects text into the currently focused application by temporarily
/// borrowing the clipboard and simulating Cmd+V.
///
/// The original clipboard contents are saved and restored after a short delay.
final class TextInjector: @unchecked Sendable {

    /// Injects text into the focused window via clipboard paste.
    /// - Parameter text: The text to inject.
    func injectText(_ text: String) {
        print("📝 Preparing to inject text: '\(text)'")
        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general

            // Save existing clipboard contents
            let savedItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
                let newItem = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        newItem.setData(data, forType: type)
                    }
                }
                return newItem
            }

            // Set our text
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            // Brief delay for macOS to register the new clipboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                print("📋 Simulating Cmd+V paste...")
                // Simulate Cmd+V
                self.simulatePaste()

                // Restore original clipboard after paste completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pasteboard.clearContents()
                    if let saved = savedItems {
                        pasteboard.writeObjects(saved)
                    }
                }
            }
        }
    }

    // MARK: - Private

    /// Simulates a Cmd+V keystroke using CGEvent.
    private func simulatePaste() {
        // Virtual key 0x09 = 'V'
        let cmdVDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)

        cmdVDown?.flags = .maskCommand
        cmdVUp?.flags = .maskCommand

        cmdVDown?.post(tap: .cghidEventTap)
        cmdVUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Placeholders

    /// Types a placeholder string directly into the focused window using individual keystrokes.
    /// Does not alter the clipboard.
    func typePlaceholder(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for char in text.utf16 {
            var codeUnit = char
            if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            {
                eventDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
                eventUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
                eventDown.post(tap: .cghidEventTap)
                eventUp.post(tap: .cghidEventTap)
            }
        }
    }

    /// Deletes the placeholder string by sending multiple backspace (Delete) keystrokes.
    func deletePlaceholder(length: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        let backspaceVirtualKey: CGKeyCode = 0x33  // kVK_Delete

        for _ in 0..<length {
            if let eventDown = CGEvent(
                keyboardEventSource: source, virtualKey: backspaceVirtualKey, keyDown: true),
                let eventUp = CGEvent(
                    keyboardEventSource: source, virtualKey: backspaceVirtualKey, keyDown: false)
            {
                eventDown.post(tap: .cghidEventTap)
                eventUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Animated Placeholders

    private var animationTask: Task<Void, Never>?

    /// Starts an animated "[processing...]" placeholder loop
    func startProcessingAnimation() {
        stopProcessingAnimation()

        animationTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            let base = "processing"
            let frames = [".", "..", "..."]
            var frameIdx = 0

            self.typePlaceholder(base)
            var currentLength = base.count

            while !Task.isCancelled {
                let frame = frames[frameIdx]
                self.typePlaceholder(frame)
                currentLength = base.count + frame.count

                do {
                    // Update every 500ms
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    // Sleep was cancelled
                    break
                }

                if Task.isCancelled { break }

                self.deletePlaceholder(length: frame.count)
                currentLength = base.count
                frameIdx = (frameIdx + 1) % frames.count
            }

            // Clean up the entire string that was printed thus far
            self.deletePlaceholder(length: currentLength)
        }
    }

    /// Stops the placeholder animation and immediately cleans up the text
    func stopProcessingAnimation() {
        animationTask?.cancel()
        animationTask = nil
    }
}
