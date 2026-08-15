import XCTest
@testable import VoiceTyper

final class VoiceConversationStorageTests: XCTestCase {

    var tempDirectory: URL!
    var storage: VoiceConversationStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetyper_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        storage = VoiceConversationStorage(baseDirectory: tempDirectory)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testEnsureDirectoriesExist() throws {
        try storage.ensureDirectoriesExist()

        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.audioDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.textDirectory.path))
    }

    func testSaveWavAndTextFiles() throws {
        let syntheticAudio = AudioTestHelper.generateSineWave(frequency: 440.0, durationSeconds: 0.5)
        let sampleTranscript = "Decision: OpenSCAD remains geometric source of truth."

        let result = try storage.saveConversation(
            audioFrames: syntheticAudio,
            transcription: sampleTranscript,
            identifier: "test01"
        )

        // Assert files exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.audioURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.textURL.path))

        // Assert text content matches
        let savedText = try String(contentsOf: result.textURL, encoding: .utf8)
        XCTAssertEqual(savedText, sampleTranscript)

        // Assert WAV header validity
        let wavData = try Data(contentsOf: result.audioURL)
        XCTAssertGreaterThanOrEqual(wavData.count, 44) // Standard WAV header is 44 bytes

        let riffString = String(data: wavData.subdata(in: 0..<4), encoding: .utf8)
        let waveString = String(data: wavData.subdata(in: 8..<12), encoding: .utf8)
        let fmtString = String(data: wavData.subdata(in: 12..<16), encoding: .utf8)

        XCTAssertEqual(riffString, "RIFF")
        XCTAssertEqual(waveString, "WAVE")
        XCTAssertEqual(fmtString, "fmt ")
    }

    func testCreateWavDataByteLength() {
        let sampleCount = 16000 // 1 second of 16kHz
        let samples = [Float](repeating: 0.5, count: sampleCount)
        let wavData = VoiceConversationStorage.createWavData(from: samples, sampleRate: 16000)

        // Header (44 bytes) + 16000 samples * 2 bytes = 32044 bytes
        XCTAssertEqual(wavData.count, 44 + (sampleCount * 2))
    }
}
