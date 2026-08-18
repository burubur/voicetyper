import XCTest
@testable import VoiceTyper

final class VoiceConversationStorageLapTests: XCTestCase {

    func testMultiPartFileNamingAndLapStorage() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetyper_lap_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = VoiceConversationStorage(baseDirectory: tempDir)
        let testDate = Date()
        let dummyFrames: [Float] = [Float](repeating: 0.1, count: 16000)

        // Save Part 1 (Lap 1)
        let result1 = try storage.saveConversation(
            audioFrames: dummyFrames,
            transcription: "This is part 1 of our conversation.",
            date: testDate,
            identifier: "session123",
            lap: 1
        )

        // Save Part 2 (Lap 2)
        let result2 = try storage.saveConversation(
            audioFrames: dummyFrames,
            transcription: "This is part 2 of our conversation.",
            date: testDate,
            identifier: "session123",
            lap: 2
        )

        XCTAssertTrue(result1.audioURL.lastPathComponent.contains("part1.wav"))
        XCTAssertTrue(result1.textURL.lastPathComponent.contains("part1.txt"))

        XCTAssertTrue(result2.audioURL.lastPathComponent.contains("part2.wav"))
        XCTAssertTrue(result2.textURL.lastPathComponent.contains("part2.txt"))

        // Assert files exist on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: result1.audioURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result2.audioURL.path))

        // Verify text contents
        let text1 = try String(contentsOf: result1.textURL, encoding: .utf8)
        let text2 = try String(contentsOf: result2.textURL, encoding: .utf8)

        XCTAssertTrue(text1.contains("(Part 1)"))
        XCTAssertTrue(text1.contains("This is part 1 of our conversation."))

        XCTAssertTrue(text2.contains("(Part 2)"))
        XCTAssertTrue(text2.contains("This is part 2 of our conversation."))
    }
}
