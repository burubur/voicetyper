import Cocoa

let banner = """
 __      __  _           _______                     
 \\ \\    / / (_)         |__   __|                    
  \\ \\  / /__ _  ___ ___    | |_   _ _ __   ___ _ __ 
   \\ \\/ / _ \\ |/ __/ _ \\   | | | | | '_ \\ / _ \\ '__|
    \\  / (_) | | (_|  __/   | | |_| | |_) |  __/ |   
     \\/ \\___/|_|\\___\\___|   |_|\\__, | .__/ \\___|_|   
                                __/ | |              
                               |___/|_|              
VoiceTyper — Native macOS Offline Voice-to-Text Dictation
"""

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    Swift.print(banner)
    Swift.print("""
Usage: voicetyper [options]

Options:
  -d, --debug     Run in foreground with verbose debug logging
  -h, --help      Show this help message and exit

Controls:
  Right Option    Hold to dictate, release to transcribe & type
  Escape          Cancel / abort in-flight dictation
""")
    exit(0)
}

let isDebugMode = CommandLine.arguments.contains("--debug") || CommandLine.arguments.contains("-d")

if isDebugMode {
    Swift.print(banner)
}

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
