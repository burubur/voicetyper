import XCTest
@testable import VoiceTyper

final class MemoryVaultIngesterTests: XCTestCase {

    func testClassifyDecisionType() {
        let transcript = "Decision: OpenSCAD will remain the geometric single source of truth for all CAD models."
        let payload = MemoryVaultIngester.classifyTranscript(transcript)

        XCTAssertEqual(payload.recordType, "decision")
        XCTAssertTrue(payload.tags.contains("voice"))
        XCTAssertTrue(payload.tags.contains("memo"))
        XCTAssertTrue(payload.tags.contains("decision"))
        XCTAssertEqual(payload.content, transcript)
    }

    func testClassifyLearningType() {
        let transcript = "Learned: Internal domain packages in Go must not import external HTTP or DB drivers."
        let payload = MemoryVaultIngester.classifyTranscript(transcript)

        XCTAssertEqual(payload.recordType, "learn")
        XCTAssertTrue(payload.tags.contains("voice"))
        XCTAssertTrue(payload.tags.contains("memo"))
        XCTAssertTrue(payload.tags.contains("learning"))
    }

    func testClassifyRuleType() {
        let transcript = "Rule: Never commit node_modules or secret credentials into git repository."
        let payload = MemoryVaultIngester.classifyTranscript(transcript)

        XCTAssertEqual(payload.recordType, "rule")
        XCTAssertTrue(payload.tags.contains("voice"))
        XCTAssertTrue(payload.tags.contains("memo"))
        XCTAssertTrue(payload.tags.contains("rule"))
    }

    func testClassifyFactType() {
        let transcript = "Fact: The west elevation trench depth is 500mm below baseline Z 0."
        let payload = MemoryVaultIngester.classifyTranscript(transcript)

        XCTAssertEqual(payload.recordType, "fact")
        XCTAssertTrue(payload.tags.contains("voice"))
        XCTAssertTrue(payload.tags.contains("memo"))
        XCTAssertTrue(payload.tags.contains("fact"))
    }

    func testClassifyDefaultConversationType() {
        let transcript = "We are reviewing the morning standup progress across all modules."
        let payload = MemoryVaultIngester.classifyTranscript(transcript)

        XCTAssertEqual(payload.recordType, "conversation")
        XCTAssertTrue(payload.tags.contains("voice"))
        XCTAssertTrue(payload.tags.contains("memo"))
        XCTAssertTrue(payload.tags.contains("standup"))
    }

    func testBuildCLIArguments() {
        let payload = MemoryVaultIngester.Payload(
            content: "Decision: Standardize on Shift + Right Option for voice memory logging",
            recordType: "decision",
            tags: ["voice", "memo", "decision", "hotkey"],
            scope: "project"
        )

        let args = MemoryVaultIngester.buildArguments(for: payload)

        XCTAssertEqual(args[0], "store")
        XCTAssertEqual(args[1], payload.content)
        XCTAssertTrue(args.contains("--type=decision"))
        XCTAssertTrue(args.contains("--scope=project"))
        XCTAssertTrue(args.contains { $0.starts(with: "--tags=") })
    }
}
