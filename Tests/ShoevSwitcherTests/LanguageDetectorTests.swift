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

    func testEmbeddedLexiconConvertsCommonWrongLayoutWord() {
        let detector = LanguageDetector(rules: RuleStore())
        for (original, alternative) in [("ghbdtn", "привет"), ("Ghbdtn", "Привет")] {
            XCTAssertEqual(
                detector.decision(
                    original: original,
                    alternative: alternative,
                    sourceLanguage: .english,
                    applicationBundleIdentifier: nil
                ),
                .convert(ConversionCandidate(
                    original: original,
                    replacement: alternative,
                    sourceLanguage: .english,
                    targetLanguage: .russian
                ))
            )
        }
    }

    func testConvertsShortEnglishWordsTypedOnRussianLayout() {
        let detector = LanguageDetector(rules: RuleStore())
        for (original, alternative) in [("пфн", "gay"), ("пгн", "guy")] {
            let expected = DetectionDecision.convert(ConversionCandidate(
                original: original,
                replacement: alternative,
                sourceLanguage: .russian,
                targetLanguage: .english
            ))
            XCTAssertEqual(
                detector.evaluate(
                    original: original,
                    alternative: alternative,
                    sourceLanguage: .russian,
                    applicationBundleIdentifier: nil,
                    context: DetectionContext()
                ).decision,
                expected,
                "scores: original=\(String(describing: EmbeddedLexicon.shared.score(for: original, language: .russian))) alternative=\(String(describing: EmbeddedLexicon.shared.score(for: alternative, language: .english)))"
            )
            XCTAssertEqual(
                detector.evaluate(
                    original: original,
                    alternative: alternative,
                    sourceLanguage: .russian,
                    applicationBundleIdentifier: nil,
                    context: DetectionContext(
                        recentLanguages: [.russian, .russian, .russian, .russian, .russian],
                        applicationLanguage: .russian
                    )
                ).decision,
                expected,
                "scores: original=\(String(describing: EmbeddedLexicon.shared.score(for: original, language: .russian))) alternative=\(String(describing: EmbeddedLexicon.shared.score(for: alternative, language: .english)))"
            )
        }
    }

    func testUnambiguousShortPairsSurviveMisleadingScoresAndRussianContext() {
        let detector = LanguageDetector(
            rules: RuleStore(),
            wordScorer: { word, language in
                if language == .russian, ["пфн", "пгн"].contains(word) { return 20 }
                if language == .english, ["gay", "guy"].contains(word) { return 1 }
                return nil
            }
        )
        for (original, alternative) in [("пфн", "gay"), ("пгн", "guy")] {
            XCTAssertEqual(
                detector.evaluate(
                    original: original,
                    alternative: alternative,
                    sourceLanguage: .russian,
                    applicationBundleIdentifier: nil,
                    context: DetectionContext(
                        recentLanguages: [.russian, .russian, .russian],
                        applicationLanguage: .russian
                    )
                ).decision,
                .convert(ConversionCandidate(
                    original: original,
                    replacement: alternative,
                    sourceLanguage: .russian,
                    targetLanguage: .english
                ))
            )
        }
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

    func testConvertsEnglishKeyFToFrequentRussianA() {
        let detector = LanguageDetector(rules: RuleStore())
        XCTAssertEqual(
            detector.decision(
                original: "f",
                alternative: "а",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil
            ),
            .convert(ConversionCandidate(
                original: "f",
                replacement: "а",
                sourceLanguage: .english,
                targetLanguage: .russian
            ))
        )
    }

    func testKeepsFrequentEnglishSingleLetters() {
        let detector = LanguageDetector(rules: RuleStore())
        for (original, alternative) in [("a", "ф"), ("i", "ш"), ("x", "ч")] {
            XCTAssertEqual(
                detector.decision(
                    original: original,
                    alternative: alternative,
                    sourceLanguage: .english,
                    applicationBundleIdentifier: nil
                ),
                .keep
            )
        }
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

    func testApplicationLanguageProvidesSmallTieBreaker() {
        let scores: [InputLanguage: [String: Double]] = [
            .english: ["xy": 5],
            .russian: ["аб": 6.6]
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
                context: DetectionContext(applicationLanguage: .russian)
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

    func testKnownThreeWordPhraseResolvesAmbiguousToken() {
        let scores: [InputLanguage: [String: Double]] = [
            .english: ["pyf.": 5],
            .russian: ["знаю": 5.4]
        ]
        let detector = LanguageDetector(rules: RuleStore(), wordScorer: { word, language in
            scores[language]?[word]
        })
        let context = DetectionContext(
            recentLanguages: [.russian, .russian],
            recentTokens: [
                ContextToken(text: "я", language: .russian),
                ContextToken(text: "не", language: .russian)
            ]
        )

        XCTAssertEqual(
            detector.evaluate(
                original: "pyf.",
                alternative: "знаю",
                sourceLanguage: .english,
                applicationBundleIdentifier: nil,
                context: context
            ).decision,
            .convert(ConversionCandidate(
                original: "pyf.",
                replacement: "знаю",
                sourceLanguage: .english,
                targetLanguage: .russian
            ))
        )
    }

    func testFullLexiconContainsCompanyNames() {
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "OpenAI", language: .english))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Microsoft", language: .english))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Yandex", language: .english))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Яндекс", language: .russian))
        XCTAssertNotNil(EmbeddedLexicon.shared.score(for: "Сбербанк", language: .russian))
    }

    func testExtendedLexiconContainsNamesSurnamesAndProfanity() {
        for word in ["Шоев", "Цукерберг", "хуесосами", "пиздануть"] {
            XCTAssertNotNil(
                EmbeddedLexicon.shared.score(for: word, language: .russian),
                "Missing Russian entry: \(word)"
            )
        }
        for word in ["Zuckerberg", "Smithson", "motherfucker", "cockwomble"] {
            XCTAssertNotNil(
                EmbeddedLexicon.shared.score(for: word, language: .english),
                "Missing English entry: \(word)"
            )
        }
    }

    func testExtendedLexiconConvertsRareNamesAndProfanity() {
        let detector = LanguageDetector(rules: RuleStore())
        let cases: [(String, String, InputLanguage)] = [
            ("ijtd", "шоев", .english),
            ("gbplfyenm", "пиздануть", .english),
            ("ьщерукагслук", "motherfucker", .russian),
            ("ягслукиукп", "zuckerberg", .russian),
        ]

        for (original, alternative, sourceLanguage) in cases {
            let targetLanguage: InputLanguage = sourceLanguage == .english ? .russian : .english
            XCTAssertEqual(
                detector.decision(
                    original: original,
                    alternative: alternative,
                    sourceLanguage: sourceLanguage,
                    applicationBundleIdentifier: nil
                ),
                .convert(ConversionCandidate(
                    original: original,
                    replacement: alternative,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )),
                "Failed to convert \(original) → \(alternative)"
            )
        }
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

    func testRuleOnlyAppliesToItsSourceLanguage() {
        let rules = RuleStore()
        rules.replaceRules([
            UserRule(
                id: 1,
                kind: .keep,
                pattern: "a",
                replacement: nil,
                language: .english,
                applicationBundleIdentifier: nil,
                createdAt: Date()
            )
        ])

        XCTAssertNotNil(rules.decision(
            original: "a",
            alternative: "ф",
            sourceLanguage: .english,
            applicationBundleIdentifier: nil
        ))
        XCTAssertNil(rules.decision(
            original: "a",
            alternative: "ф",
            sourceLanguage: .russian,
            applicationBundleIdentifier: nil
        ))
    }
}
