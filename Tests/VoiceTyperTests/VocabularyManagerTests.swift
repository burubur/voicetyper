import XCTest
@testable import VoiceTyper

final class VocabularyManagerTests: XCTestCase {

    func testParseGlossaryFromMemoryJSON() {
        let sampleJSON = """
        [
            {"term": "OpenSCAD", "definition": "3D CAD modeling software"},
            {"term": "minkowski", "definition": "OpenSCAD CSG mathematical sum operator"},
            {"term": "Bouwplank", "definition": "Timber frame for geodesic layout"},
            {"term": "Saka Guru", "definition": "Four main central columns of Javanese mosque"},
            {"term": "AggregateRoot", "definition": "DDD root entity governing transaction boundary"}
        ]
        """
        let data = Data(sampleJSON.utf8)
        let terms = VocabularyManager.parseGlossaryTerms(from: data)

        XCTAssertEqual(terms.count, 5)
        XCTAssertTrue(terms.contains("OpenSCAD"))
        XCTAssertTrue(terms.contains("minkowski"))
        XCTAssertTrue(terms.contains("Bouwplank"))
        XCTAssertTrue(terms.contains("Saka Guru"))
        XCTAssertTrue(terms.contains("AggregateRoot"))
    }

    func testDeduplicationAndNormalization() {
        let rawTerms = [
            " OpenSCAD ",
            "openscad",
            "minkowski()",
            "  Bouwplank  ",
            "",
            "   ",
            "Saka Guru",
            "saka guru"
        ]

        let cleaned = VocabularyManager.sanitizeAndDeduplicate(terms: rawTerms)
        
        // Should remove empty strings, strip whitespace & brackets, and deduplicate case-insensitively
        XCTAssertEqual(cleaned.count, 4)
        XCTAssertTrue(cleaned.contains("OpenSCAD") || cleaned.contains("openscad"))
        XCTAssertTrue(cleaned.contains("minkowski"))
        XCTAssertTrue(cleaned.contains("Bouwplank"))
        XCTAssertTrue(cleaned.contains("Saka Guru"))
    }

    func testBuildWhisperPromptWithWordBudget() {
        let terms = [
            "OpenSCAD",
            "minkowski",
            "Bouwplank",
            "Saka Guru",
            "AggregateRoot",
            "TresJS",
            "ValueObject",
            "Ring Balk",
            "sherpa-onnx"
        ]

        let prompt = VocabularyManager.buildWhisperPrompt(from: terms, maxWords: 50)
        
        // Must contain technical prefix and glossary items
        XCTAssertTrue(prompt.starts(with: "Context vocabulary:"))
        XCTAssertTrue(prompt.contains("OpenSCAD"))
        XCTAssertTrue(prompt.contains("minkowski"))
        XCTAssertTrue(prompt.contains("Bouwplank"))
        XCTAssertTrue(prompt.contains("Saka Guru"))
        XCTAssertTrue(prompt.contains("AggregateRoot"))
    }

    func testBuildWhisperPromptExceedingBudgetTruncatesCleanly() {
        // Generate 100 terms
        let manyTerms = (1...100).map { "TechnicalKeyword\($0)" }
        let prompt = VocabularyManager.buildWhisperPrompt(from: manyTerms, maxWords: 15)
        
        let words = prompt.split(separator: " ")
        XCTAssertLessThanOrEqual(words.count, 18) // Prefix words + budget
        XCTAssertFalse(prompt.hasSuffix(",")) // Cleanly trimmed without trailing punctuation
    }

    func testBuildParakeetHotwordsTable() {
        let terms = ["OpenSCAD", "minkowski", "Bouwplank"]
        let hotwords = VocabularyManager.buildParakeetHotwords(from: terms, boostScore: 2.5)

        XCTAssertTrue(hotwords.contains("OpenSCAD : 2.5"))
        XCTAssertTrue(hotwords.contains("minkowski : 2.5"))
        XCTAssertTrue(hotwords.contains("Bouwplank : 2.5"))
    }

    func testFallbackToStaticDefaultTerms() {
        let defaults = VocabularyManager.defaultTechnicalTerms
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertTrue(defaults.contains("OpenSCAD"))
        XCTAssertTrue(defaults.contains("Go"))
        XCTAssertTrue(defaults.contains("Swift"))
    }
}
