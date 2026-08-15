import Foundation

/// Manages dynamic domain vocabulary extraction, caching, and prompt synthesis
/// from the active `memory` graph vault and local ubiquitous language glossaries.
public final class VocabularyManager: Sendable {

    /// Default built-in domain dictionary for technical and monorepo terminology.
    public static let defaultTechnicalTerms: [String] = [
        "OpenSCAD",
        "minkowski",
        "Bouwplank",
        "Saka Guru",
        "Ring Balk",
        "AggregateRoot",
        "ValueObject",
        "DomainEvent",
        "TresJS",
        "Three.js",
        "sherpa-onnx",
        "whisper.cpp",
        "Swift",
        "Go",
        "Golang",
        "DDD",
        "BoQ",
        "RAB",
        "west_elevation",
        "east_elevation",
        "VoiceTyper",
        "DRFTR"
    ]

    /// Parses terms from a JSON structure (e.g., from `memory term list` or exported glossary).
    public static func parseGlossaryTerms(from data: Data) -> [String] {
        struct TermItem: Decodable {
            let term: String
        }

        if let list = try? JSONDecoder().decode([TermItem].self, from: data) {
            return sanitizeAndDeduplicate(terms: list.map(\.term))
        }

        if let stringContent = String(data: data, encoding: .utf8) {
            let lines = stringContent.components(separatedBy: .newlines)
            return sanitizeAndDeduplicate(terms: lines)
        }

        return []
    }

    /// Cleans, normalizes, and deduplicates a list of terms case-insensitively.
    public static func sanitizeAndDeduplicate(terms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in terms {
            var term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip trailing parentheses e.g. "minkowski()" -> "minkowski"
            if term.hasSuffix("()") {
                term = String(term.dropLast(2)).trimmingCharacters(in: .whitespaces)
            }

            if term.isEmpty { continue }

            let lower = term.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                result.append(term)
            }
        }

        return result
    }

    /// Formats an array of terms into a natural Whisper initial prompt string capped at `maxWords`.
    public static func buildWhisperPrompt(from terms: [String], maxWords: Int = 150) -> String {
        let cleanTerms = sanitizeAndDeduplicate(terms: terms)
        if cleanTerms.isEmpty {
            return ""
        }

        let prefix = "Context vocabulary:"
        var selectedTerms: [String] = []
        var wordCount = prefix.split(separator: " ").count

        for term in cleanTerms {
            let termWordCount = term.split(separator: " ").count
            if wordCount + termWordCount > maxWords {
                break
            }
            selectedTerms.append(term)
            wordCount += termWordCount
        }

        if selectedTerms.isEmpty {
            return ""
        }

        let joined = selectedTerms.joined(separator: ", ")
        return "\(prefix) \(joined)."
    }

    /// Builds a hotwords table string with boost scores for Parakeet / sherpa-onnx.
    public static func buildParakeetHotwords(from terms: [String], boostScore: Float = 2.5) -> String {
        let cleanTerms = sanitizeAndDeduplicate(terms: terms)
        return cleanTerms
            .map { "\($0) : \(boostScore)" }
            .joined(separator: "\n")
    }

    /// Fetches terms dynamically by executing the local `memory term list` CLI.
    public static func fetchVocabularyFromMemoryCLI() async -> [String] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["memory", "term", "list", "--json"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let terms = parseGlossaryTerms(from: data)
                    continuation.resume(returning: terms)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Loads active vocabulary from `memory` CLI, local cache file `~/.voicetyper/vocabulary.txt`,
    /// or falls back to built-in default technical terms.
    public static func loadActiveVocabulary() async -> [String] {
        // 1. Try fetching from live memory CLI
        let liveTerms = await fetchVocabularyFromMemoryCLI()
        if !liveTerms.isEmpty {
            return sanitizeAndDeduplicate(terms: liveTerms + defaultTechnicalTerms)
        }

        // 2. Check local user vocabulary cache (~/.voicetyper/vocabulary.txt)
        let cacheURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voicetyper")
            .appendingPathComponent("vocabulary.txt")

        if let cachedText = try? String(contentsOf: cacheURL, encoding: .utf8) {
            let terms = cachedText.components(separatedBy: .newlines)
            let cleaned = sanitizeAndDeduplicate(terms: terms + defaultTechnicalTerms)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        // 3. Fallback to default built-in terminology
        return defaultTechnicalTerms
    }
}
