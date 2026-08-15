import Foundation

/// Sanitizes transcribed text, prevents prompt leakage hallucinations,
/// and restores canonical ubiquitous language term casing.
public final class VocabularySanitizer: Sendable {

    /// Detects if Whisper hallucinated by echoing words directly from the injected initial prompt.
    public static func isPromptLeakage(transcription: String, injectedPrompt: String?) -> Bool {
        guard let prompt = injectedPrompt, !prompt.isEmpty else {
            return false
        }

        let cleanTranscript = transcription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if cleanTranscript.isEmpty {
            return false
        }

        // Exact match against full prompt
        if cleanTranscript == cleanPrompt {
            return true
        }

        // Exact match against prompt with "context vocabulary:" prefix removed
        let prefixRemoved = cleanPrompt.replacingOccurrences(of: "context vocabulary:", with: "").trimmingCharacters(in: .whitespaces)
        if cleanTranscript == prefixRemoved {
            return true
        }

        // Check if transcription words are an exact subset of prompt words without genuine conversational verbs
        let transcriptWords = Set(cleanTranscript.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let promptWords = Set(cleanPrompt.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        if transcriptWords.isEmpty {
            return false
        }

        // If >= 90% of transcript words are inside prompt words and transcript has no common English conversational glue
        let intersection = transcriptWords.intersection(promptWords)
        let ratio = Float(intersection.count) / Float(transcriptWords.count)
        
        let conversationalWords: Set<String> = ["is", "the", "a", "an", "we", "need", "to", "please", "can", "you", "for", "in", "at", "with", "this", "that", "how", "what", "should", "will"]
        let hasConversationalGlue = !transcriptWords.intersection(conversationalWords).isEmpty

        if ratio >= 0.85 && !hasConversationalGlue {
            return true
        }

        return false
    }

    /// Restores canonical casing and collapses phonetic spacing for known vocabulary terms.
    public static func restoreCanonicalTerms(in text: String, vocabulary: [String]) -> String {
        var result = text

        for term in vocabulary {
            // 1. Direct case-insensitive replacement for single-word or multi-word term
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: term)
            }

            // 2. Common spaced phonetic variations (e.g. "open scad" -> "OpenSCAD", "min kowski" -> "minkowski")
            let spacedVariants: [(variant: String, canonical: String)] = [
                ("open scad", "OpenSCAD"),
                ("min kowski", "minkowski"),
                ("bouw plank", "Bouwplank"),
                ("saka guru", "Saka Guru"),
                ("ring balk", "Ring Balk"),
                ("aggregate root", "AggregateRoot"),
                ("value object", "ValueObject"),
                ("tres js", "TresJS"),
                ("sharp onyx", "sherpa-onnx")
            ]

            for variant in spacedVariants where term.lowercased() == variant.canonical.lowercased() {
                let varPattern = "\\b" + NSRegularExpression.escapedPattern(for: variant.variant) + "\\b"
                if let regex = try? NSRegularExpression(pattern: varPattern, options: .caseInsensitive) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: variant.canonical)
                }
            }
        }

        return result
    }

    /// Complete post-processing pipeline: checks prompt leakage, cleans noise tokens,
    /// and restores canonical domain terminology.
    public static func sanitizeOutput(
        transcription: String,
        injectedPrompt: String?,
        activeVocabulary: [String]
    ) -> String {
        if isPromptLeakage(transcription: transcription, injectedPrompt: injectedPrompt) {
            return ""
        }

        let restored = restoreCanonicalTerms(in: transcription, vocabulary: activeVocabulary)
        return restored.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
