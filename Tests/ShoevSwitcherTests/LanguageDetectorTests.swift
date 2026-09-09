import XCTest
@testable import ShoevSwitcher

final class LanguageDetectorTests: XCTestCase {
    func testConvertsWhenOnlyAlternativeIsKnown() {
        let rules = RuleStore()
        let known: [InputLanguage: Set<String>] = [
            .english: ["hello"],
            .russian: ["привет"]
        ]
        let detector = LanguageDetector(rules: rules) { word, language in
            known[language, default: []].contains(word.lowercased())
        }

        XCTAssertEqual(
            detector.decision(
                original: "ghbdtn",
                alternative: "привет",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil
            ),
            .convert(ConversionCandidate(
                original: "ghbdtn",
                replacement: "привет",
                sourceLanguage: .english,
                targetLanguage: .russian
            ))
        )
    }

    func testKeepsKnownOriginal() {
        let rules = RuleStore()
        let detector = LanguageDetector(rules: rules) { word, language in
            language == .english && word == "hello"
        }

        XCTAssertEqual(
            detector.decision(
                original: "hello",
                alternative: "руддщ",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil
            ),
            .keep
        )
    }

    func testKeepsValidShortEnglishWord() {
        let detector = LanguageDetector(rules: RuleStore())
        XCTAssertEqual(
            detector.decision(
                original: "hi",
                alternative: "рш",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil
            ),
            .keep
        )
    }

    func testConvertsSingleLetterWithEmbeddedFrequencyData() {
        let detector = LanguageDetector(rules: RuleStore())
        XCTAssertEqual(
            detector.decision(
                original: "z",
                alternative: "я",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil
            ),
            .convert(ConversionCandidate(
                original: "z",
                replacement: "я",
                sourceLanguage: .english,
                targetLanguage: .russian
            ))
        )
    }

    func testPhraseTypedOnEnglishKeysBecomesRussianFromFirstWord() {
        let detector = LanguageDetector(rules: RuleStore())
        let first = detector.evaluate(
            original: "z",
            alternative: "я",
            sourceLanguage: .english,
            applicationBundleIdentifier: nil,
            context: DetectionContext()
        )
        XCTAssertEqual(
            first.decision,
            .convert(ConversionCandidate(
                original: "z",
                replacement: "я",
                sourceLanguage: .english,
                targetLanguage: .russian
            ))
        )

        let second = detector.evaluate(
            original: "не",
            alternative: "yt",
            sourceLanguage: .russian,
            applicationBundleIdentifier: nil,
            context: DetectionContext(recentLanguages: [.russian])
        )
        XCTAssertEqual(second.decision, .keep)

        let third = detector.evaluate(
            original: "знаю",
            alternative: "pyf.",
            sourceLanguage: .russian,
            applicationBundleIdentifier: nil,
            context: DetectionContext(recentLanguages: [.russian, .russian])
        )
        XCTAssertEqual(third.decision, .keep)
    }

    func testContextHelpsAnAmbiguousShortWord() {
        let scores: [InputLanguage: [String: Double]] = [
            .english: ["xy": 5],
            .russian: ["аб": 6.2]
        ]
        let detector = LanguageDetector(rules: RuleStore(), wordScorer: { word, language in
            scores[language]?[word]
        })

        XCTAssertEqual(
            detector.evaluate(
                original: "xy",
                alternative: "аб",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil,
                context: DetectionContext()
            ).decision,
            .keep
        )
        XCTAssertEqual(
            detector.evaluate(
                original: "xy",
                alternative: "аб",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil,
                context: DetectionContext(recentLanguages: [.russian, .russian, .russian])
            ).decision,
            .convert(ConversionCandidate(
                original: "xy",
                replacement: "аб",
                sourceLanguage: .english,
                targetLanguage: .russian
            ))
        )
    }

    func testRareKnownBrandIsProtectedFromPlausibleAlternative() {
        let scores: [InputLanguage: [String: Double]] = [
            .english: ["brand": 1.2],
            .russian: ["слово": 4]
        ]
        let detector = LanguageDetector(rules: RuleStore(), wordScorer: { word, language in
            scores[language]?[word]
        })

        XCTAssertEqual(
            detector.evaluate(
                original: "brand",
                alternative: "слово",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil,
                context: DetectionContext(recentLanguages: [.russian, .russian, .russian])
            ).decision,
            .keep
        )
    }

    func testFullLexiconContainsCompanyNames() {
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "OpenAI", language: .english))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Microsoft", language: .english))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Yandex", language: .english))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Яндекс", language: .russian))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Сбербанк", language: .russian))
    }

    func testExplicitRuleTakesPriority() {
        let rules = RuleStore()
        rules.replaceRules([
            UserRule(
                id: 1,
                kind: .convert,
                pattern: "abc",
                replacement: "абв",
                language: nil,
                applicationBundleIdentifier: nil,
                createdAt: Date()
            )
        ])
        let detector = LanguageDetector(rules: rules) { _, _ in false }

        XCTAssertEqual(
            detector.decision(
                original: "abc",
                alternative: "фис",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil
            ),
            .convert(ConversionCandidate(
                original: "abc",
                replacement: "абв",
                sourceLanguage: .english,
                targetLanguage: .russian
            ))
        )
    }
}
