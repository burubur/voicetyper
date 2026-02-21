import Cocoa

let isDebugMode = CommandLine.arguments.contains("--debug") || CommandLine.arguments.contains("-d")

/// Shadows the global print function to only output when running in debug mode.
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    if isDebugMode {
        let output = items.map { "\($0)" }.joined(separator: separator)
        Swift.print(output, terminator: terminator)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
// Run as menu bar agent (no Dock icon, no main window)
app.setActivationPolicy(.accessory)
app.run()
