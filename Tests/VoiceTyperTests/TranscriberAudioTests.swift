import XCTest
@testable import VoiceTyper

final class TranscriberAudioTests: XCTestCase {

    func testSilenceAudioRejectionWithActivePrompt() async throws {
        let mockTranscriber = MockTranscriber()
        let prompt = "Context vocabulary: OpenSCAD, minkowski, Bouwplank, Saka Guru, AggregateRoot."
        mockTranscriber.setInitialPrompt(prompt)

        // 2 seconds of pure silence PCM frames
        let silenceAudio = AudioTestHelper.generateSilence(durationSeconds: 2.0)
        
        let result = try await mockTranscriber.transcribe(audioFrames: silenceAudio)
        
        // Assert: Silence must result in empty text, rejecting any leaked prompt tokens
        XCTAssertEqual(result, "")
        XCTAssertEqual(mockTranscriber.lastReceivedAudioFrameCount, 32000)
    }

    func testTranscriberReceivesConfiguredInitialPrompt() async throws {
        let mockTranscriber = MockTranscriber()
        let expectedPrompt = "Context vocabulary: OpenSCAD, minkowski, Bouwplank."
        mockTranscriber.setInitialPrompt(expectedPrompt)
        mockTranscriber.mockedOutput = "OpenSCAD minkowski difference"

        let audio = AudioTestHelper.generateSineWave(frequency: 440.0, durationSeconds: 1.0)
        let output = try await mockTranscriber.transcribe(audioFrames: audio)

        XCTAssertEqual(mockTranscriber.configuredPrompt, expectedPrompt)
        XCTAssertEqual(output, "OpenSCAD minkowski difference")
    }

    func testEndToEndVocabularyPipelineSimulation() async throws {
        let mockTranscriber = MockTranscriber()
        let vocabulary = ["OpenSCAD", "minkowski", "Bouwplank"]
        let prompt = VocabularyManager.buildWhisperPrompt(from: vocabulary)
        
        mockTranscriber.setInitialPrompt(prompt)
        // Simulate speech where model output has minor casing variation
        mockTranscriber.mockedOutput = "lets render open scad with min kowski"

        let audio = AudioTestHelper.generateSineWave(frequency: 440.0, durationSeconds: 1.0)
        let rawTranscription = try await mockTranscriber.transcribe(audioFrames: audio)

        // Run through VocabularySanitizer
        let sanitized = VocabularySanitizer.sanitizeOutput(
            transcription: rawTranscription,
            injectedPrompt: prompt,
            activeVocabulary: vocabulary
        )

        XCTAssertEqual(sanitized, "lets render OpenSCAD with minkowski")
    }
}
