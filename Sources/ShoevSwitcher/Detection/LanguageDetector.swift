import Foundation

protocol RuleProviding: AnyObject {
    func decision(
        original: String,
        alternative: String,
        sourceLanguage: InputLanguage,
        applicationBundleIdentifier: String?
    ) -> DetectionDecision?

    func isAccepted(_ word: String, language: InputLanguage) -> Bool
}

final class LanguageDetector {
    typealias WordValidator = (_ word: String, _ language: InputLanguage) -> Bool
    typealias WordScorer = (_ word: String, _ language: InputLanguage) -> Double?
    typealias OriginalProtector = (_ word: String, _ language: InputLanguage) -> Bool
    typealias PhraseScorer = (_ words: [String], _ language: InputLanguage) -> Double

    private let rules: RuleProviding
    private let wordScorer: WordScorer
    private let originalProtector: OriginalProtector
    private let phraseScorer: PhraseScorer

    init(rules: RuleProviding, wordValidator: WordValidator? = nil) {
        self.rules = rules
        if let wordValidator {
            self.wordScorer = { word, language in
                wordValidator(word, language) ? 6 : nil
            }
            self.originalProtector = wordValidator
        } else {
            self.wordScorer = EmbeddedLexicon.shared.score
            self.originalProtector = EmbeddedLexicon.shared.protectsOriginal
        }
        self.phraseScorer = PhraseLexicon.shared.bonus
    }

    init(
        rules: RuleProviding,
        wordScorer: @escaping WordScorer,
        originalProtector: OriginalProtector? = nil,
        phraseScorer: @escaping PhraseScorer = PhraseLexicon.shared.bonus
    ) {
        self.rules = rules
        self.wordScorer = wordScorer
        self.originalProtector = originalProtector ?? { word, language in
            wordScorer(word, language) != nil
        }
        self.phraseScorer = phraseScorer
    }

    func decision(
        original: String,
        alternative: String,
        sourceLanguage: InputLanguage,
        applicationBundleIdentifier: String?
    ) -> DetectionDecision {
        evaluate(
            original: original,
            alternative: alternative,
            sourceLanguage: sourceLanguage,
            applicationBundleIdentifier: applicationBundleIdentifier,
            context: DetectionContext()
        ).decision
    }

    func isKnown(_ word: String, language: InputLanguage) -> Bool {
        rules.isAccepted(word, language: language) || wordScorer(word, language) != nil
    }

    func evaluate(
        original: String,
        alternative: String,
        sourceLanguage: InputLanguage,
        applicationBundleIdentifier: String?,
        context: DetectionContext
    ) -> DetectionEvaluation {
        let targetLanguage: InputLanguage = sourceLanguage == .english ? .russian : .english

        if let ruleDecision = rules.decision(
            original: original,
            alternative: alternative,
            sourceLanguage: sourceLanguage,
            applicationBundleIdentifier: applicationBundleIdentifier
        ) {
            let likelyLanguage: InputLanguage
            switch ruleDecision {
            case .keep: likelyLanguage = sourceLanguage
            case .convert(let candidate): likelyLanguage = candidate.targetLanguage
            }
            return DetectionEvaluation(decision: ruleDecision, likelyLanguage: likelyLanguage)
        }

        if isUnambiguousShortLayoutPair(
            original: original,
            alternative: alternative,
            sourceLanguage: sourceLanguage
        ) {
            return DetectionEvaluation(
                decision: .convert(ConversionCandidate(
                    original: original,
                    replacement: alternative,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )),
                likelyLanguage: targetLanguage
            )
        }

        guard isEligible(original), isEligible(alternative) else {
            return DetectionEvaluation(decision: .keep, likelyLanguage: sourceLanguage)
        }

        let originalScore = score(original, language: sourceLanguage, context: context)
        let alternativeScore = score(alternative, language: targetLanguage, context: context)
        let likelyLanguage = likelyLanguage(
            sourceLanguage: sourceLanguage,
            originalScore: originalScore,
            targetLanguage: targetLanguage,
            alternativeScore: alternativeScore
        )

        guard let alternativeScore else {
            return DetectionEvaluation(decision: .keep, likelyLanguage: likelyLanguage)
        }

        // A rare known source token is often a name, brand or technical term.
        // Its presence should protect it from a merely plausible alternative.
        let protectsOriginal = rules.isAccepted(original, language: sourceLanguage)
            || originalProtector(original, sourceLanguage)
        let originalValue = originalScore.map {
            protectsOriginal ? max($0, knownOriginalFloor) : $0
        } ?? unknownWordScore
        var margin = requiredMargin(
            for: original.count,
            contextSupportsTarget: context.dominantLanguage == targetLanguage
        )
        // Single Latin letters are valid dictionary entries, but that alone must not
        // outweigh a clearly more frequent one-letter word in the other language
        // (for example, English-key `f` is Russian `а`).
        if protectsOriginal, original.count > 1 {
            margin += 0.65
        }
        guard alternativeScore - originalValue >= margin else {
            return DetectionEvaluation(decision: .keep, likelyLanguage: likelyLanguage)
        }

        return DetectionEvaluation(
            decision: .convert(ConversionCandidate(
                original: original,
                replacement: alternative,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )),
            likelyLanguage: targetLanguage
        )
    }

    private func score(
        _ word: String,
        language: InputLanguage,
        context: DetectionContext
    ) -> Double? {
        var value: Double
        if rules.isAccepted(word, language: language) {
            value = 12
        } else if let lexiconScore = wordScorer(word, language) {
            value = lexiconScore
        } else {
            return nil
        }

        if context.dominantLanguage == language {
            value += min(Double(context.recentLanguages.count) * 0.12, 0.48)
        }
        if context.applicationLanguage == language {
            value += 0.28
        }
        let phraseWords = contiguousWords(for: language, context: context) + [word]
        value += phraseScorer(phraseWords, language)
        return value
    }

    private func contiguousWords(
        for language: InputLanguage,
        context: DetectionContext
    ) -> [String] {
        var result: [String] = []
        for token in context.recentTokens.reversed() {
            guard token.language == language else { break }
            result.insert(token.text, at: 0)
            if result.count == 2 { break }
        }
        return result
    }

    private func likelyLanguage(
        sourceLanguage: InputLanguage,
        originalScore: Double?,
        targetLanguage: InputLanguage,
        alternativeScore: Double?
    ) -> InputLanguage {
        switch (originalScore, alternativeScore) {
        case let (.some(original), .some(alternative)):
            return alternative > original ? targetLanguage : sourceLanguage
        case (.none, .some):
            return targetLanguage
        default:
            return sourceLanguage
        }
    }

    private func isEligible(_ word: String) -> Bool {
        guard !word.isEmpty, word.count <= 64 else { return false }
        let forbidden = CharacterSet(charactersIn: "0123456789@/:\\_=")
        if word.unicodeScalars.contains(where: forbidden.contains) { return false }

        let letters = word.unicodeScalars.filter(CharacterSet.letters.contains)
        guard !letters.isEmpty else { return false }

        let hasLowercase = word.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasUppercase = word.rangeOfCharacter(from: .uppercaseLetters) != nil
        if hasLowercase && hasUppercase && word.dropFirst().contains(where: { $0.isUppercase }) {
            return false
        }
        return true
    }

    private func isUnambiguousShortLayoutPair(
        original: String,
        alternative: String,
        sourceLanguage: InputLanguage
    ) -> Bool {
        guard sourceLanguage == .russian else { return false }
        let pair = "\(original.lowercased())\u{0}\(alternative.lowercased())"
        return Self.unambiguousRussianToEnglishPairs.contains(pair)
    }

    private func requiredMargin(for length: Int, contextSupportsTarget: Bool) -> Double {
        let base: Double
        switch length {
        case 1: base = 1.65
        case 2: base = 1.15
        default: base = 0.75
        }
        return contextSupportsTarget ? max(0.6, base - 0.35) : base
    }

    private let unknownWordScore = 2.0
    private let knownOriginalFloor = 3.5
    private static let unambiguousRussianToEnglishPairs: Set<String> = [
        "пфн\u{0}gay",
        "пгн\u{0}guy"
    ]
}
