import XCTest
@testable import VoiceTyper

final class VocabularySanitizerTests: XCTestCase {

    func testDetectAndRejectPromptLeakageExactMatch() {
        let injectedPrompt = "Context vocabulary: OpenSCAD, minkowski, Bouwplank, Saka Guru, AggregateRoot."
        let hallucinatedOutput = "Context vocabulary: OpenSCAD, minkowski, Bouwplank, Saka Guru, AggregateRoot."
        
        let isLeaked = VocabularySanitizer.isPromptLeakage(
            transcription: hallucinatedOutput,
            injectedPrompt: injectedPrompt
        )
        XCTAssertTrue(isLeaked)

        let sanitized = VocabularySanitizer.sanitizeOutput(
            transcription: hallucinatedOutput,
            injectedPrompt: injectedPrompt,
            activeVocabulary: ["OpenSCAD", "minkowski", "Bouwplank"]
        )
        XCTAssertEqual(sanitized, "")
    }

    func testDetectAndRejectPromptLeakagePartialMatch() {
        let injectedPrompt = "Context vocabulary: OpenSCAD, minkowski, Bouwplank, Saka Guru, AggregateRoot."
        let hallucinatedOutput = "OpenSCAD minkowski Bouwplank Saka Guru AggregateRoot"
        
        let isLeaked = VocabularySanitizer.isPromptLeakage(
            transcription: hallucinatedOutput,
            injectedPrompt: injectedPrompt
        )
        XCTAssertTrue(isLeaked)
    }

    func testAllowLegitimateSpeechContainingVocabulary() {
        let injectedPrompt = "Context vocabulary: OpenSCAD, minkowski, Bouwplank, Saka Guru, AggregateRoot."
        let validSpeech = "Please calculate the minkowski difference in OpenSCAD before building the model."
        
        let isLeaked = VocabularySanitizer.isPromptLeakage(
            transcription: validSpeech,
            injectedPrompt: injectedPrompt
        )
        XCTAssertFalse(isLeaked)
    }

    func testRestoreCanonicalCasingAndSpacing() {
        let rawTranscript = "we need to check the open scad model and min kowski sum for the bouw plank."
        let vocabulary = ["OpenSCAD", "minkowski", "Bouwplank"]
        
        let cleaned = VocabularySanitizer.restoreCanonicalTerms(
            in: rawTranscript,
            vocabulary: vocabulary
        )
        
        XCTAssertTrue(cleaned.contains("OpenSCAD"))
        XCTAssertTrue(cleaned.contains("minkowski"))
        XCTAssertTrue(cleaned.contains("Bouwplank"))
        XCTAssertFalse(cleaned.contains("open scad"))
        XCTAssertFalse(cleaned.contains("min kowski"))
        XCTAssertFalse(cleaned.contains("bouw plank"))
    }

    func testPreserveSurroundingPunctuationAndStructure() {
        let rawTranscript = "Is the AggregateRoot configured properly, or should we refactor the ValueObject?"
        let vocabulary = ["AggregateRoot", "ValueObject"]
        
        let cleaned = VocabularySanitizer.restoreCanonicalTerms(
            in: rawTranscript,
            vocabulary: vocabulary
        )
        
        XCTAssertEqual(
            cleaned,
            "Is the AggregateRoot configured properly, or should we refactor the ValueObject?"
        )
    }
}
