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

    private let rules: RuleProviding
    private let wordScorer: WordScorer

    init(rules: RuleProviding, wordValidator: WordValidator? = nil) {
        self.rules = rules
        if let wordValidator {
            self.wordScorer = { word, language in
                wordValidator(word, language) ? 6 : nil
            }
        } else {
            self.wordScorer = EmbeddedLexicon.shared.score
        }
    }

    init(rules: RuleProviding, wordScorer: @escaping WordScorer) {
        self.rules = rules
        self.wordScorer = wordScorer
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
        let originalValue = originalScore.map { max($0, knownOriginalFloor) } ?? unknownWordScore
        var margin = requiredMargin(
            for: original.count,
            contextSupportsTarget: context.dominantLanguage == targetLanguage
        )
        if originalScore != nil {
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
        return value
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
}
