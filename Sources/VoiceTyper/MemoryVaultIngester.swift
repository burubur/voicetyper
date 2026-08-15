import Foundation

/// Ingests transcribed speech into structured memory payloads and handles
/// heuristic intent classification for the `memory` CLI.
public final class MemoryVaultIngester: Sendable {

    public struct Payload: Sendable, Equatable {
        public let content: String
        public let recordType: String
        public let tags: [String]
        public let scope: String

        public init(content: String, recordType: String, tags: [String], scope: String = "project") {
            self.content = content
            self.recordType = recordType
            self.tags = tags
            self.scope = scope
        }
    }

    /// Classifies a transcribed speech string into a typed memory payload with tags.
    public static func classifyTranscript(_ transcript: String, scope: String = "project") -> Payload {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.starts(with: "decision:") || lower.starts(with: "decided:") {
            return Payload(
                content: trimmed,
                recordType: "decision",
                tags: ["voice", "memo", "decision"],
                scope: scope
            )
        }

        if lower.starts(with: "learned:") || lower.starts(with: "learning:") {
            return Payload(
                content: trimmed,
                recordType: "learn",
                tags: ["voice", "memo", "learning"],
                scope: scope
            )
        }

        if lower.starts(with: "rule:") {
            return Payload(
                content: trimmed,
                recordType: "rule",
                tags: ["voice", "memo", "rule"],
                scope: scope
            )
        }

        if lower.starts(with: "fact:") || lower.starts(with: "discovery:") {
            return Payload(
                content: trimmed,
                recordType: "fact",
                tags: ["voice", "memo", "fact"],
                scope: scope
            )
        }

        // Default: general conversation / standup memo
        return Payload(
            content: trimmed,
            recordType: "conversation",
            tags: ["voice", "memo", "standup"],
            scope: scope
        )
    }

    /// Builds command-line arguments for executing `memory store`.
    public static func buildArguments(for payload: Payload) -> [String] {
        var args = ["store", payload.content]
        args.append("--type=\(payload.recordType)")
        args.append("--scope=\(payload.scope)")
        if !payload.tags.isEmpty {
            args.append("--tags=\(payload.tags.joined(separator: ","))")
        }
        return args
    }
}
