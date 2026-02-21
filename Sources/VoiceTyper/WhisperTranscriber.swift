import Foundation
import SwiftWhisper

// MARK: - Transcriber Protocol

/// Abstraction for speech-to-text transcription, enabling testability.
protocol Transcriber: Sendable {
    func transcribe(audioFrames: [Float]) async throws -> String
}

// MARK: - WhisperTranscriber

/// Production adapter that uses whisper.cpp via SwiftWhisper for local,
/// offline speech-to-text transcription.
final class WhisperTranscriber: Transcriber, @unchecked Sendable {
    private let whisper: Whisper

    /// Initializes the transcriber by loading a GGML model file.
    /// - Parameter modelURL: Path to the whisper GGML model (e.g. `ggml-base.en.bin`).
    /// - Throws: If the model file cannot be loaded.
    init(modelURL: URL) throws {
        self.whisper = Whisper(fromFileURL: modelURL)
    }

    /// Transcribes 16kHz mono PCM float audio frames into text.
    /// - Parameter audioFrames: Array of Float samples at 16kHz sample rate.
    /// - Returns: The transcribed text, or empty string if silence was detected.
    func transcribe(audioFrames: [Float]) async throws -> String {
        let segments = try await whisper.transcribe(audioFrames: audioFrames)
        let text = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)

        // Whisper often returns artifacts for silence — reject known patterns
        let silencePatterns = [
            "[BLANK_AUDIO]", "(silence)", "[silence]", "(blank audio)",
            "you", "Thank you.", "Thanks for watching!",
        ]
        for pattern in silencePatterns {
            if text.lowercased() == pattern.lowercased() {
                return ""
            }
        }

        return text
    }

    // MARK: - Model Discovery

    /// Default model directory: `~/.voicetyper/`
    static var defaultModelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".voicetyper")
    }

    /// Model filename (configurable via WHISPER_MODEL env var, .xcconfig, or UserDefaults)
    static var configuredModelFilename: String {
        // 1. Check environment variable
        if let env = ProcessInfo.processInfo.environment["WHISPER_MODEL"], !env.isEmpty {
            return env.hasSuffix(".bin") ? env : "\(env).bin"
        }

        // 2. Check local `.xcconfig` file
        let xcconfigURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".xcconfig")
        if let content = try? String(contentsOf: xcconfigURL, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count == 2, parts[0] == "WHISPER_MODEL" {
                    let model = parts[1]
                    return model.hasSuffix(".bin") ? model : "\(model).bin"
                }
            }
        }

        // 3. Check macOS UserDefaults
        if let def = UserDefaults.standard.string(forKey: "WHISPER_MODEL"), !def.isEmpty {
            return def.hasSuffix(".bin") ? def : "\(def).bin"
        }

        // Default
        return "ggml-base.en.bin"
    }

    /// Resolved model file URL based on configuration
    static var defaultModelURL: URL {
        defaultModelDirectory.appendingPathComponent(configuredModelFilename)
    }

    /// Checks if the configured model file exists and prints instructions if missing.
    /// - Returns: The model URL if it exists, nil otherwise.
    static func resolveModelURL() -> URL? {
        let url = defaultModelURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        print(
            """
            ⚠️  Whisper model not found at: \(url.path)

            If you configured a custom model via WHISPER_MODEL, make sure it's downloaded.
            To download the default model:
              mkdir -p ~/.voicetyper
              curl -L -o ~/.voicetyper/ggml-base.en.bin \\
                https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

            Available models (trade-off: size vs accuracy vs speed):
              • ggml-tiny.en.bin        (~75MB)  — fastest, least accurate
              • ggml-base.en.bin        (~142MB) — good balance ✓ (recommended)
              • ggml-small.en.bin       (~466MB) — more accurate
            """)
        return nil
    }
}
