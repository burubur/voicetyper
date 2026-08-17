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
    private(set) var activeVocabulary: [String] = []
    private(set) var initialPrompt: String?
    private var initialPromptCString: UnsafeMutablePointer<CChar>?

    /// Initializes the transcriber by loading a GGML model file.
    /// - Parameter modelURL: Path to the whisper GGML model (e.g. `ggml-base.en.bin`).
    /// - Throws: If the model file cannot be loaded.
    init(modelURL: URL, vocabulary: [String] = []) throws {
        self.whisper = Whisper(fromFileURL: modelURL)
        if !vocabulary.isEmpty {
            self.setVocabulary(terms: vocabulary)
        }
    }

    deinit {
        if let ptr = initialPromptCString {
            free(ptr)
        }
    }

    /// Sets or updates the active vocabulary and initial prompt biasing.
    func setVocabulary(terms: [String]) {
        self.activeVocabulary = terms
        let prompt = VocabularyManager.buildWhisperPrompt(from: terms)
        self.initialPrompt = prompt.isEmpty ? nil : prompt
        if let ptr = initialPromptCString {
            free(ptr)
            initialPromptCString = nil
        }
        if let p = self.initialPrompt {
            let ptr = strdup(p)
            self.initialPromptCString = ptr
            self.whisper.params.initial_prompt = UnsafePointer(ptr)
        } else {
            self.whisper.params.initial_prompt = nil
        }
    }

    /// Transcribes 16kHz mono PCM float audio frames into text.
    /// - Parameter audioFrames: Array of Float samples at 16kHz sample rate.
    /// - Returns: The transcribed text, or empty string if silence was detected.
    func transcribe(audioFrames: [Float]) async throws -> String {
        let segments = try await whisper.transcribe(audioFrames: audioFrames)
        var text = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Strip out pure noise/audio tags anywhere they appear
        let noiseTags = ["[BLANK_AUDIO]", "(silence)", "[silence]", "(blank audio)"]
        for tag in noiseTags {
            while let range = text.range(of: tag, options: .caseInsensitive) {
                text.removeSubrange(range)
            }
        }
        
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Reject the entire transcription if it exactly matches a known whisper hallucination phrase
        let exactHallucinations = ["you", "Thank you.", "Thanks for watching!"]
        for hallucination in exactHallucinations {
            if text.lowercased() == hallucination.lowercased() {
                return ""
            }
        }

        if text.isEmpty {
            return ""
        }

        // 3. Apply post-processing sanitizer (detects prompt leakage & restores canonical casing)
        return VocabularySanitizer.sanitizeOutput(
            transcription: text,
            injectedPrompt: self.initialPrompt,
            activeVocabulary: self.activeVocabulary
        )
    }

    // MARK: - Model Discovery

    struct ModelOption: Sendable, Equatable {
        let filename: String
        let displayName: String
        let sizeDescription: String
    }

    static let availableModels: [ModelOption] = [
        ModelOption(filename: "ggml-tiny.en.bin", displayName: "Tiny English (Whisper)", sizeDescription: "~75MB (Fastest)"),
        ModelOption(filename: "ggml-base.en.bin", displayName: "Base English (Whisper)", sizeDescription: "~142MB (Balanced)"),
        ModelOption(filename: "ggml-small.en.bin", displayName: "Small English (Whisper)", sizeDescription: "~466MB (Accurate)"),
        ModelOption(filename: "ggml-medium.en.bin", displayName: "Medium English (Whisper)", sizeDescription: "~1.5GB (High Accuracy)"),
        ModelOption(filename: "ggml-large-v3.bin", displayName: "Large v3 Multilingual (Whisper)", sizeDescription: "~3.1GB (Max Accuracy)"),
        ModelOption(filename: "parakeet-unified-0.6b", displayName: "NVIDIA Parakeet Unified 0.6B (ONNX)", sizeDescription: "~240MB (3x-5x Fast STT)"),
        ModelOption(filename: "parakeet-tdt-110m", displayName: "NVIDIA Parakeet TDT 110M (ONNX)", sizeDescription: "~110MB (Ultra Fast)")
    ]

    /// Checks if a given model file or directory exists in `~/.voicetyper/`
    static func isModelDownloaded(filename: String) -> Bool {
        if filename.contains("parakeet") {
            let assetName = filename.contains("110m")
                ? "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"
                : "sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming"
            let dirURL = defaultModelDirectory.appendingPathComponent(assetName)
            return FileManager.default.fileExists(atPath: dirURL.path)
        }
        let name = filename.hasSuffix(".bin") ? filename : "\(filename).bin"
        let url = defaultModelDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Default model directory: `~/.voicetyper/`
    static var defaultModelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".voicetyper")
    }

    /// Model filename (configurable via UserDefaults UI selection, WHISPER_MODEL env var, or .xcconfig)
    static var configuredModelFilename: String {
        // 1. Check macOS UserDefaults (UI User Selection takes priority)
        if let def = UserDefaults.standard.string(forKey: "WHISPER_MODEL"), !def.isEmpty {
            return def.contains("parakeet") ? def : (def.hasSuffix(".bin") ? def : "\(def).bin")
        }

        // 2. Check environment variable
        if let env = ProcessInfo.processInfo.environment["WHISPER_MODEL"], !env.isEmpty {
            return env.contains("parakeet") ? env : (env.hasSuffix(".bin") ? env : "\(env).bin")
        }

        // 3. Check local `.xcconfig` file
        let xcconfigURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".xcconfig")
        if let content = try? String(contentsOf: xcconfigURL, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count == 2, parts[0] == "WHISPER_MODEL" {
                    let model = parts[1]
                    return model.contains("parakeet") ? model : (model.hasSuffix(".bin") ? model : "\(model).bin")
                }
            }
        }

        // Default: Whisper Base English (GGML)
        return "ggml-base.en.bin"
    }

    /// Resolved model file URL based on configuration
    static var defaultModelURL: URL {
        let filename = configuredModelFilename
        if filename.contains("parakeet") {
            let dirname = filename == "parakeet-unified-0.6b"
                ? "sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming"
                : "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"
            return defaultModelDirectory.appendingPathComponent(dirname)
        }
        return defaultModelDirectory.appendingPathComponent(filename)
    }

    /// Checks if the configured model file exists and prints instructions if missing.
    /// Falls back to any downloaded model if configured model is missing.
    /// - Returns: The model URL if it exists or a downloaded fallback exists, nil otherwise.
    static func resolveModelURL() -> (Bool, URL?) {
        let url = defaultModelURL
        if FileManager.default.fileExists(atPath: url.path) {
            return (true, url)
        }

        // Fallback: check if any available model is downloaded
        for option in availableModels {
            if isModelDownloaded(filename: option.filename) {
                let dirname = option.filename.contains("parakeet")
                    ? (option.filename == "parakeet-unified-0.6b"
                        ? "sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming"
                        : "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8")
                    : (option.filename.hasSuffix(".bin") ? option.filename : "\(option.filename).bin")
                let fallbackURL = defaultModelDirectory.appendingPathComponent(dirname)
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    print("⚠️  Configured model '\(configuredModelFilename)' not found. Falling back to downloaded model '\(option.filename)'.")
                    UserDefaults.standard.set(option.filename, forKey: "WHISPER_MODEL")
                    return (true, fallbackURL)
                }
            }
        }

        print(
            """
            ⚠️  Whisper model not found at: \(url.path)

            If you configured a custom model via WHISPER_MODEL, make sure it's downloaded.
            To download the default model:
              mkdir -p ~/.voicetyper
              curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(configuredModelFilename)" -o "\(url.path)"
            
            Available models (trade-off: size vs accuracy vs speed):
              • ggml-tiny.en.bin        (~75MB)  — fastest, least accurate
              • ggml-base.en.bin        (~142MB) — good balance ✓ (recommended)
              • ggml-small.en.bin       (~466MB) — more accurate
            """)
        return (false, nil)
    }
}
