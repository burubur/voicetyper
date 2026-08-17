import Foundation

/// Manages self-upgrading, source tracking, and version inspection for VoiceTyper.
public final class UpgradeManager: Sendable {
    public static let shared = UpgradeManager()

    public static let currentVersion = "v0.5.0"

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

    /// Resolves the installed binary destination path.
    public static func determineInstallPath() -> String {
        let defaultPath = "/usr/local/bin/voicetyper"
        let execPath = CommandLine.arguments[0]
        let execURL = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: execURL.path) && !execURL.path.contains(".build") {
            return execURL.path
        }
        if FileManager.default.fileExists(atPath: defaultPath) {
            return defaultPath
        }
        let localPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/voicetyper").path
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }
        return defaultPath
    }

    /// Executes the self-upgrade sequence.
    public static func runUpgrade(noPull: Bool = false, customSourceDir: String? = nil) {
        Swift.print("✦ VOICETYPER SELF-UPGRADE")
        Swift.print("───────────────────────────────────────────────────────────────────────────")

        let installPath = determineInstallPath()
        let detectedSource = findSourceRepoDir(customSourceDir: customSourceDir)
        let oldCommit = getGitCommit(in: detectedSource ?? ".")

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
        buildProcess.arguments = ["build", "-c", "release"]
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

        Swift.print("📦 Installing binary to \(installPath)...")
        let installDir = (installPath as NSString).deletingLastPathComponent

        if FileManager.default.isWritableFile(atPath: installDir) || FileManager.default.isWritableFile(atPath: installPath) {
            do {
                if FileManager.default.fileExists(atPath: installPath) {
                    try FileManager.default.removeItem(atPath: installPath)
                }
                try FileManager.default.copyItem(atPath: builtBin, toPath: installPath)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
                Swift.print("✓ Replaced binary at \(installPath)")
            } catch {
                Swift.print("❌ Failed to copy binary: \(error)")
                exit(1)
            }
        } else {
            Swift.print("🔑 Administrator privileges required to copy to \(installPath)...")
            let sudoCp = Process()
            sudoCp.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            sudoCp.arguments = ["cp", builtBin, installPath]
            do {
                try sudoCp.run()
                sudoCp.waitUntilExit()
                guard sudoCp.terminationStatus == 0 else {
                    Swift.print("❌ Sudo copy failed.")
                    exit(1)
                }
                let sudoChmod = Process()
                sudoChmod.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                sudoChmod.arguments = ["chmod", "+x", installPath]
                try sudoChmod.run()
                sudoChmod.waitUntilExit()
                Swift.print("✓ Replaced binary at \(installPath) (via sudo)")
            } catch {
                Swift.print("❌ Sudo process error: \(error)")
                exit(1)
            }
        }

        Swift.print("🚀 Restarting VoiceTyper menu bar agent in background...")
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
        restart.executableURL = URL(fileURLWithPath: installPath)
        let logURL = voicetyperHome.appendingPathComponent("app.log")
        if FileManager.default.fileExists(atPath: logURL.path),
           let logHandle = try? FileHandle(forWritingTo: logURL) {
            restart.standardOutput = logHandle
            restart.standardError = logHandle
        }
        try? restart.run()

        Swift.print("───────────────────────────────────────────────────────────────────────────")
        Swift.print("✅ VoiceTyper successfully upgraded! (\(oldCommit) → \(newCommit))")
        Swift.print("   Binary Path: \(installPath)")
        Swift.print("   Status     : Running in background (Menu Bar mic icon)")
    }
}
