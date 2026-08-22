import Foundation

/// Version details holding version and commit metadata.
public struct VersionDetails: Sendable {
    public let version: String
    public let commit: String
}

/// Manages self-upgrading, source tracking, and version inspection for VoiceTyper.
public final class UpgradeManager: Sendable {
    public static let shared = UpgradeManager()

    public static let currentVersion = "0.5.0"

    public static let banner = """
\u{001B}[1m\u{001B}[36m __      __  _           _______                     
 \\ \\    / / (_)         |__   __|                    
  \\ \\  / /__ _  ___ ___    | |_   _ _ __   ___ _ __ 
   \\ \\/ / _ \\ |/ __/ _ \\   | | | | | '_ \\ / _ \\ '__|
    \\  / (_) | | (_|  __/   | | |_| | |_) |  __/ |   
     \\/ \\___/|_|\\___\\___|   |_|\\__, | .__/ \\___|_|   
                                __/ | |              
                               |___/|_|              \u{001B}[0m
\u{001B}[1mNative macOS Offline Voice Dictation & Conversation Vault (v\(currentVersion))\u{001B}[0m
\u{001B}[36mRepository: https://github.com/burubur/voicetyper\u{001B}[0m
"""

    public static var voicetyperHome: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".voicetyper")
    }

    public static var sourceRepoCacheURL: URL {
        voicetyperHome.appendingPathComponent("source_repo")
    }

    /// Fetches short git commit hash for a directory.
    public static func getGitCommit(in directory: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "rev-parse", "--short", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let commit = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return commit.isEmpty ? "release" : commit
            }
        } catch {}
        return "release"
    }

    /// Fetches git commit logs between two commit hashes.
    public static func getGitLogBetween(in directory: String, fromCommit: String, toCommit: String) -> [String] {
        guard !fromCommit.isEmpty, !toCommit.isEmpty, fromCommit != toCommit, fromCommit != "release", toCommit != "release" else {
            return []
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "log", "--oneline", "\(fromCommit)..\(toCommit)", "-n", "10"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8) {
                    return str.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        } catch {}
        return []
    }

    /// Inspects an installed binary path and returns its version details.
    public static func getBinaryVersionInfo(at binaryPath: String) -> VersionDetails {
        let fallback = VersionDetails(version: currentVersion, commit: "release")
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            return fallback
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    var ver = currentVersion
                    var commit = "release"
                    if let start = str.range(of: "VoiceTyper ")?.upperBound {
                        let rem = str[start...]
                        if let parenStart = rem.range(of: "(")?.lowerBound {
                            ver = String(rem[..<parenStart]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let parenEnd = rem.range(of: ")")?.lowerBound {
                                commit = String(rem[rem.index(after: parenStart)..<parenEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } else {
                            ver = String(rem).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    return VersionDetails(version: ver, commit: commit)
                }
            }
        } catch {}
        return fallback
    }

    /// Checks if a git repository directory has a remote configured.
    public static func hasGitRemote(in directory: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "remote"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !output.isEmpty
            }
        } catch {}
        return false
    }

    /// Records the source repository root path to `~/.voicetyper/source_repo` for future upgrades.
    public static func recordSourceRepo(_ path: String) {
        try? FileManager.default.createDirectory(at: voicetyperHome, withIntermediateDirectories: true)
        try? path.trimmingCharacters(in: .whitespacesAndNewlines).write(to: sourceRepoCacheURL, atomically: true, encoding: .utf8)
    }

    /// Locates the VoiceTyper source repository directory.
    public static func findSourceRepoDir(customSourceDir: String? = nil) -> String? {
        if let custom = customSourceDir, !custom.isEmpty {
            let pkg = URL(fileURLWithPath: custom).appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) {
                recordSourceRepo(custom)
                return custom
            }
        }

        if let env = ProcessInfo.processInfo.environment["VOICETYPER_SOURCE_DIR"], !env.isEmpty {
            let pkg = URL(fileURLWithPath: env).appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) {
                return env
            }
        }

        let cwd = FileManager.default.currentDirectoryPath
        let cwdPkg = URL(fileURLWithPath: cwd).appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: cwdPkg.path),
           let content = try? String(contentsOf: cwdPkg, encoding: .utf8), content.contains("VoiceTyper") {
            recordSourceRepo(cwd)
            return cwd
        }

        if let cached = try? String(contentsOf: sourceRepoCacheURL, encoding: .utf8) {
            let trimmed = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            let cachedPkg = URL(fileURLWithPath: trimmed).appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: cachedPkg.path) {
                return trimmed
            }
        }

        return nil
    }

    /// Determines the target installation path for the macOS application bundle.
    /// Checks /Applications first, falling back to ~/Applications if /Applications is not writable.
    public static func determineAppBundlePath() -> String {
        let systemApps = "/Applications"
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        if FileManager.default.isWritableFile(atPath: systemApps) {
            return (systemApps as NSString).appendingPathComponent("VoiceTyper.app")
        } else {
            try? FileManager.default.createDirectory(atPath: userApps, withIntermediateDirectories: true)
            return (userApps as NSString).appendingPathComponent("VoiceTyper.app")
        }
    }

    /// Resolves the installed binary destination path.
    /// Prefers ~/.local/bin/voicetyper (user-owned, zero sudo/password required).
    public static func determineInstallPath() -> String {
        let localDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        let localPath = localDir.appendingPathComponent("voicetyper").path

        let execPath = CommandLine.arguments[0]
        let execURL = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()

        // If currently running from an installed binary in a user-writable path:
        if FileManager.default.fileExists(atPath: execURL.path) && !execURL.path.contains(".build") {
            let parentDir = (execURL.path as NSString).deletingLastPathComponent
            if FileManager.default.isWritableFile(atPath: parentDir) {
                return execURL.path
            }
        }

        // Default to ~/.local/bin/voicetyper
        try? FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        return localPath
    }

    /// Executes the self-upgrade sequence.
    public static func runUpgrade(noPull: Bool = false, customSourceDir: String? = nil) {
        Swift.print(banner)
        Swift.print("✦ VOICETYPER SELF-UPGRADE")
        Swift.print("───────────────────────────────────────────────────────────────────────────")

        let installPath = determineInstallPath()
        let detectedSource = findSourceRepoDir(customSourceDir: customSourceDir)

        // 1. Capture old version and git commit info before upgrade
        let oldInfo = getBinaryVersionInfo(at: installPath)
        let oldCommit = (oldInfo.commit != "release" && !oldInfo.commit.isEmpty) ? oldInfo.commit : getGitCommit(in: detectedSource ?? ".")

        var sourceDir = detectedSource
        var isTempClone = false

        if sourceDir == nil {
            Swift.print("↓ Cloning latest source repository from https://github.com/burubur/voicetyper.git...")
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("voicetyper-upgrade-\(UUID().uuidString)").path
            let gitClone = Process()
            gitClone.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            gitClone.arguments = ["clone", "--depth", "1", "https://github.com/burubur/voicetyper.git", tempDir]
            do {
                try gitClone.run()
                gitClone.waitUntilExit()
                if gitClone.terminationStatus == 0 {
                    sourceDir = tempDir
                    isTempClone = true
                } else {
                    Swift.print("❌ Failed to clone repository.")
                    exit(1)
                }
            } catch {
                Swift.print("❌ Git clone error: \(error)")
                exit(1)
            }
        }

        guard let validSourceDir = sourceDir else {
            Swift.print("❌ Unable to locate or download VoiceTyper source repository.")
            exit(1)
        }

        defer {
            if isTempClone {
                try? FileManager.default.removeItem(atPath: validSourceDir)
            }
        }

        Swift.print("📂 Source Repository: \(validSourceDir)")

        if !isTempClone && !noPull && hasGitRemote(in: validSourceDir) {
            Swift.print("↓ Pulling latest revisions from git remote...")
            let gitPull = Process()
            gitPull.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            gitPull.arguments = ["-C", validSourceDir, "pull", "--rebase"]
            do {
                try gitPull.run()
                gitPull.waitUntilExit()
                if gitPull.terminationStatus == 0 {
                    Swift.print("✓ Git repository synchronized with remote origin.")
                } else {
                    Swift.print("! Git pull notice (continuing with current source revision).")
                }
            } catch {
                Swift.print("! Git pull notice (continuing with current source revision).")
            }
        }

        let newCommit = getGitCommit(in: validSourceDir)

        Swift.print("✦ Compiling VoiceTyper in release mode...")
        let buildProcess = Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        var buildArgs = ["build", "-c", "release"]
        let infoPlistPath = URL(fileURLWithPath: validSourceDir).appendingPathComponent("Resources/Info.plist").path
        if FileManager.default.fileExists(atPath: infoPlistPath) {
            buildArgs.append(contentsOf: ["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlistPath])
        }
        buildProcess.arguments = buildArgs
        buildProcess.currentDirectoryURL = URL(fileURLWithPath: validSourceDir)

        do {
            try buildProcess.run()
            buildProcess.waitUntilExit()
            guard buildProcess.terminationStatus == 0 else {
                Swift.print("❌ Swift release compilation failed (exit code: \(buildProcess.terminationStatus)).")
                exit(1)
            }
            Swift.print("✓ Build successful.")
        } catch {
            Swift.print("❌ Build process error: \(error)")
            exit(1)
        }

        let builtBin = URL(fileURLWithPath: validSourceDir)
            .appendingPathComponent(".build/release/VoiceTyper").path

        guard FileManager.default.fileExists(atPath: builtBin) else {
            Swift.print("❌ Compiled binary not found at: \(builtBin)")
            exit(1)
        }

        let appBundlePath = determineAppBundlePath()
        Swift.print("📦 Packaging macOS Application Bundle to \(appBundlePath)...")

        let bundleScript = URL(fileURLWithPath: validSourceDir).appendingPathComponent("scripts/bundle_app.sh").path
        if FileManager.default.fileExists(atPath: bundleScript) {
            let bundleProc = Process()
            bundleProc.executableURL = URL(fileURLWithPath: "/bin/bash")
            bundleProc.arguments = [bundleScript, "--bin", builtBin, "--output", appBundlePath, "--resources", URL(fileURLWithPath: validSourceDir).appendingPathComponent("Resources").path]
            try? bundleProc.run()
            bundleProc.waitUntilExit()
        } else {
            // Manual fallback bundling
            let appContents = URL(fileURLWithPath: appBundlePath).appendingPathComponent("Contents")
            let appMacOS = appContents.appendingPathComponent("MacOS")
            let appResources = appContents.appendingPathComponent("Resources")
            try? FileManager.default.createDirectory(at: appMacOS, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: appResources, withIntermediateDirectories: true)

            let appBin = appMacOS.appendingPathComponent("VoiceTyper").path
            try? FileManager.default.removeItem(atPath: appBin)
            try? FileManager.default.copyItem(atPath: builtBin, toPath: appBin)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appBin)

            let infoPlist = URL(fileURLWithPath: validSourceDir).appendingPathComponent("Resources/Info.plist").path
            if FileManager.default.fileExists(atPath: infoPlist) {
                try? FileManager.default.copyItem(atPath: infoPlist, toPath: appContents.appendingPathComponent("Info.plist").path)
            }
            let pkgInfo = appContents.appendingPathComponent("PkgInfo").path
            try? "APPL????".write(toFile: pkgInfo, atomically: true, encoding: .utf8)
        }

        // Install or link CLI binary
        Swift.print("📦 Linking CLI binary to \(installPath)...")
        let installDir = (installPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: installDir), withIntermediateDirectories: true)

        let appInternalBin = URL(fileURLWithPath: appBundlePath).appendingPathComponent("Contents/MacOS/VoiceTyper").path
        let sourceForCli = FileManager.default.fileExists(atPath: appInternalBin) ? appInternalBin : builtBin

        do {
            if FileManager.default.fileExists(atPath: installPath) {
                try FileManager.default.removeItem(atPath: installPath)
            }
            try FileManager.default.createSymbolicLink(atPath: installPath, withDestinationPath: sourceForCli)
            Swift.print("✓ Linked CLI binary at \(installPath)")
        } catch {
            // Fallback to copy if symlink creation fails
            try? FileManager.default.removeItem(atPath: installPath)
            try? FileManager.default.copyItem(atPath: sourceForCli, toPath: installPath)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
            Swift.print("✓ Copied binary at \(installPath)")
        }

        // Ad-hoc code signing for macOS application bundle
        let entitlementsPath = URL(fileURLWithPath: validSourceDir)
            .appendingPathComponent("Resources/VoiceTyper.entitlements").path
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        if FileManager.default.fileExists(atPath: entitlementsPath) {
            codesign.arguments = ["--force", "--deep", "--sign", "-", "--entitlements", entitlementsPath, appBundlePath]
        } else {
            codesign.arguments = ["--force", "--deep", "--sign", "-", appBundlePath]
        }
        try? codesign.run()
        codesign.waitUntilExit()

        // Register with LaunchServices
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.fileExists(atPath: lsregister) {
            let regProc = Process()
            regProc.executableURL = URL(fileURLWithPath: lsregister)
            regProc.arguments = ["-f", appBundlePath]
            try? regProc.run()
            regProc.waitUntilExit()
        }

        Swift.print("🚀 Restarting VoiceTyper in background...")
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-i", "-x", "VoiceTyper"]
        try? pkill.run()
        pkill.waitUntilExit()

        let pkillLower = Process()
        pkillLower.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillLower.arguments = ["-i", "-x", "voicetyper"]
        try? pkillLower.run()
        pkillLower.waitUntilExit()

        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: sourceForCli)
        let logURL = voicetyperHome.appendingPathComponent("app.log")
        if FileManager.default.fileExists(atPath: logURL.path),
           let logHandle = try? FileHandle(forWritingTo: logURL) {
            restart.standardOutput = logHandle
            restart.standardError = logHandle
        }
        try? restart.run()

        let effectiveNewCommit = !newCommit.isEmpty ? newCommit : getGitCommit(in: validSourceDir)

        Swift.print("")
        Swift.print("───────────────────────────────────────────────────────────────────────────")
        Swift.print("✦ Version Transition:")
        if !oldCommit.isEmpty && oldCommit != "release" {
            Swift.print("   • Previous : \(oldInfo.version) (commit: \(oldCommit))")
        } else {
            Swift.print("   • Previous : \(oldInfo.version)")
        }

        if !effectiveNewCommit.isEmpty && effectiveNewCommit != "release" {
            if oldInfo.version == currentVersion && oldCommit == effectiveNewCommit {
                Swift.print("   • Current  : \(currentVersion) (commit: \(effectiveNewCommit), up to date)")
            } else {
                Swift.print("   • Current  : \(currentVersion) (commit: \(effectiveNewCommit))")
            }
        } else {
            Swift.print("   • Current  : \(currentVersion)")
        }

        if oldCommit != effectiveNewCommit && oldCommit != "release" && effectiveNewCommit != "release" {
            let logs = getGitLogBetween(in: validSourceDir, fromCommit: oldCommit, toCommit: effectiveNewCommit)
            if !logs.isEmpty {
                Swift.print("\n✦ Upgraded Commits (\(oldCommit)..\(effectiveNewCommit)):")
                for entry in logs {
                    Swift.print("   • \(entry)")
                }
            }
        }

        Swift.print("───────────────────────────────────────────────────────────────────────────")
        if oldCommit != effectiveNewCommit && oldCommit != "release" {
            Swift.print("✅ VoiceTyper successfully upgraded! (\(oldInfo.version) [\(oldCommit)] → \(currentVersion) [\(effectiveNewCommit)])")
        } else {
            Swift.print("✅ VoiceTyper is already up to date (\(currentVersion) [\(effectiveNewCommit)])")
        }
        Swift.print("   App Bundle : \(appBundlePath)")
        Swift.print("   CLI Path   : \(installPath)")
        Swift.print("   Status     : Running in background (Menu Bar mic icon)")
    }
}
