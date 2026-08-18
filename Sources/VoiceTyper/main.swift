import Cocoa
import Foundation

let banner = UpgradeManager.banner

let args = CommandLine.arguments

// 1. Subcommand: version / -v / --version
if args.contains("version") || args.contains("-v") || args.contains("--version") {
    let sourceDir = UpgradeManager.findSourceRepoDir() ?? "."
    let commit = UpgradeManager.getGitCommit(in: sourceDir)
    Swift.print("VoiceTyper \(UpgradeManager.currentVersion) (\(commit))")
    exit(0)
}

// 2. Subcommand: help / -h / --help
if args.contains("help") || args.contains("-h") || args.contains("--help") {
    Swift.print(banner)
    Swift.print("""
Usage: voicetyper [command] [options]

Commands:
  (default)       Launch VoiceTyper menu bar background agent
  upgrade         Self-upgrade voicetyper binary from git source
  version         Show version and commit hash
  status          Show configuration and storage paths
  help            Show this help message

Options:
  -d, --debug     Run in foreground with verbose debug logging
  --no-pull       Skip git pull during upgrade
  --source-dir    Specify custom source repository directory for upgrade

Controls:
  Right Option          Hold to dictate, release to transcribe & inject text
  Shift + Right Option  Hold to record voice conversation memo (~/.voicetyper/conversation/)
  Escape / Ctrl+C       Cancel / abort in-flight dictation
""")
    exit(0)
}

// 3. Subcommand: status
if args.contains("status") {
    Swift.print(banner)
    Swift.print("✦ VOICETYPER STATUS")
    Swift.print("───────────────────────────────────────────────────────────────────────────")
    let home = UpgradeManager.voicetyperHome.path
    let binary = UpgradeManager.determineInstallPath()
    let model = WhisperTranscriber.configuredModelFilename
    let modelDir = WhisperTranscriber.defaultModelDirectory.path
    let source = UpgradeManager.findSourceRepoDir() ?? "(none cached)"

    Swift.print("• Version      : \(UpgradeManager.currentVersion)")
    Swift.print("• Binary Path  : \(binary)")
    Swift.print("• Home Dir     : \(home)")
    Swift.print("• Active Model : \(model)")
    Swift.print("• Model Dir    : \(modelDir)")
    Swift.print("• Source Repo  : \(source)")
    Swift.print("• Memos Path   : \(home)/conversation")
    Swift.print("───────────────────────────────────────────────────────────────────────────")
    exit(0)
}

// 4. Subcommand: upgrade
if args.contains("upgrade") {
    let noPull = args.contains("--no-pull")
    var customSource: String? = nil
    for arg in args {
        if arg.hasPrefix("--source-dir=") {
            customSource = String(arg.dropFirst("--source-dir=".count))
        }
    }
    UpgradeManager.runUpgrade(noPull: noPull, customSourceDir: customSource)
    exit(0)
}

// 5. Main Application Lifecycle
let isDebugMode = args.contains("--debug") || args.contains("-d")

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
