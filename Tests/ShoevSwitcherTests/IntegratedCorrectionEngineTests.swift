import XCTest
@testable import ShoevSwitcher

private final class FakeLexicon: WordScoring {
    let values: [String: Int]
    init(_ values: [String: Int]) { self.values = values }
    func score(for word: String, language: SpellLanguage) -> Int? { values[word] }
}

final class SpellCorrectionEngineTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "ShoevSpellTests-\(UUID().uuidString)"
        let result = UserDefaults(suiteName: suite)!
        result.set(3, forKey: SpellPreferenceKey.minimumLength)
        result.set(250, forKey: SpellPreferenceKey.minimumScore)
        return result
    }

    func testCorrectsSingleEdit() {
        let engine = SpellCorrectionEngine(lexicon: FakeLexicon(["привет": 500]), defaults: defaults())
        XCTAssertEqual(engine.correction(for: "превет"), Correction(original: "превет", replacement: "привет"))
    }

    func testKeepsKnownWord() {
        let engine = SpellCorrectionEngine(lexicon: FakeLexicon(["hello": 500]), defaults: defaults())
        XCTAssertNil(engine.correction(for: "hello"))
    }

    func testDoesNotCorrectShoevBrandNameToShoes() {
        let engine = SpellCorrectionEngine(lexicon: FakeLexicon(["shoes": 467, "shove": 366]), defaults: defaults())
        XCTAssertNil(engine.correction(for: "Shoev"))
    }

    func testDoesNotGuessWhenCandidatesAreTooClose() {
        let engine = SpellCorrectionEngine(lexicon: FakeLexicon(["cat": 400, "cut": 390]), defaults: defaults())
        XCTAssertNil(engine.correction(for: "cot"))
    }

    func testBundledLexiconContainsBothLanguages() {
        XCTAssertNotNil(SpellLexicon.shared.score(for: "zuckerberg", language: .english))
        XCTAssertNotNil(SpellLexicon.shared.score(for: "шоев", language: .russian))
    }

    func testBundledLexiconCorrectsRealTypos() {
        let engine = SpellCorrectionEngine(lexicon: SpellLexicon.shared, defaults: defaults())
        XCTAssertEqual(engine.correction(for: "zuckreberg")?.replacement, "zuckerberg")
        XCTAssertEqual(engine.correction(for: "превет")?.replacement, "привет")
        XCTAssertEqual(engine.correction(for: "спосибо")?.replacement, "спасибо")
        XCTAssertEqual(engine.correction(for: "пожалуста")?.replacement, "пожалуйста")
        XCTAssertEqual(engine.correction(for: "Пожайлуста")?.replacement, "Пожалуйста")
    }

    func testSpellingBaselineDoesNotAddRulesToThePersonalDiary() {
        let rules = RuleStore()
        rules.replaceRules([UserRule(id: 1, kind: .keep, pattern: "пожалуста", replacement: nil,
            language: .russian, applicationBundleIdentifier: nil, createdAt: Date())])
        let engine = SpellCorrectionEngine(lexicon: SpellLexicon.shared, defaults: defaults(), rules: rules, application: { nil })
        XCTAssertNil(engine.correction(for: "пожалуста"))
    }

    func testBundledLexiconNeverChangesKnownRussianFunctionWords() {
        let engine = SpellCorrectionEngine(lexicon: SpellLexicon.shared, defaults: defaults())
        for word in ["что", "это", "чтобы", "например"] {
            XCTAssertNil(engine.correction(for: word), "Не должно исправляться известное слово: \(word)")
        }
    }
}
