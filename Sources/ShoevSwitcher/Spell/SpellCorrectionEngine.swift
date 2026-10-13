import AppKit

final class SpellCorrectionEngine {
    private static let protectedWords: Set<String> = ["shoev"]
    // A frequency corpus contains common misspellings too. These exact spelling
    // corrections are baseline behavior, not learned or personal diary rules.
    private static let canonicalSpelling = ["пожалуста": "пожалуйста", "пожайлуста": "пожалуйста"]
    private let lexicon: WordScoring
    private let defaults: UserDefaults
    private let rules: RuleStore?
    private let application: () -> String?

    init(lexicon: WordScoring = SpellLexicon.shared, defaults: UserDefaults = .standard,
         rules: RuleStore? = nil, application: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
        self.lexicon = lexicon
        self.defaults = defaults
        self.rules = rules; self.application = application
    }

    func correction(for original: String) -> Correction? {
        if let language = SpellLanguage.detect(in: original),
           let decision = rules?.spellingDecision(original, language: language == .english ? .english : .russian, application: application()) {
            if case .convert(let candidate) = decision { return Correction(original: original, replacement: candidate.replacement) }
            return nil
        }
        let normalized = original.lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard Self.protectedWords.contains(normalized) == false,
              original.allSatisfy({ $0.isLetter }),
              original == original.lowercased() || original == original.uppercased()
                || original == original.prefix(1).uppercased() + original.dropFirst().lowercased(),
              normalized.count >= defaults.integer(forKey: SpellPreferenceKey.minimumLength),
              normalized.count <= 32,
              let language = SpellLanguage.detect(in: normalized) else { return nil }
        let minimumScore = defaults.integer(forKey: SpellPreferenceKey.minimumScore)
        if let canonical = Self.canonicalSpelling[normalized] {
            guard let score = lexicon.score(for: canonical, language: language), score >= minimumScore else { return nil }
            return Correction(original: original, replacement: restoreCase(of: original, in: canonical))
        }
        let originalScore = lexicon.score(for: normalized, language: language)
        if let originalScore, originalScore >= minimumScore { return nil }

        let candidates = editsAtDistanceOne(from: normalized, language: language)
            .compactMap { word -> SpellingCandidate? in
                let personal = originalScore == nil ? rules?.personalSpellingScore(word, language: language == .english ? .english : .russian, application: application()) : nil
                guard let score = lexicon.score(for: word, language: language) ?? personal else { return nil }
                return SpellingCandidate(word: word, score: score)
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.word < rhs.word : lhs.score > rhs.score
            }

        guard let best = candidates.first, best.score >= minimumScore else { return nil }
        if let runnerUp = candidates.dropFirst().first, best.score - runnerUp.score < 25 { return nil }
        if let originalScore {
            guard originalScore < 180, best.score >= 400, best.score - originalScore >= 200 else { return nil }
        }
        return Correction(original: original, replacement: restoreCase(of: original, in: best.word))
    }

    func isProtected(_ word: String) -> Bool {
        guard let language = SpellLanguage.detect(in: word) else { return false }
        return rules?.spellingDecision(word, language: language == .english ? .english : .russian, application: application()) == .keep
    }

    func editsAtDistanceOne(from word: String, language: SpellLanguage) -> Set<String> {
        let letters = Array(word)
        var result = Set<String>()
        result.reserveCapacity((letters.count + 1) * language.alphabet.count * 2)

        for index in letters.indices {
            var deleted = letters
            deleted.remove(at: index)
            result.insert(String(deleted))

            if index + 1 < letters.count {
                var transposed = letters
                transposed.swapAt(index, index + 1)
                result.insert(String(transposed))
            }

            for character in language.alphabet where character != letters[index] {
                var replaced = letters
                replaced[index] = character
                result.insert(String(replaced))
            }
        }

        for index in 0...letters.count {
            for character in language.alphabet {
                var inserted = letters
                inserted.insert(character, at: index)
                result.insert(String(inserted))
            }
        }
        result.remove(word)
        return result
    }

    private func restoreCase(of original: String, in replacement: String) -> String {
        if original == original.uppercased() { return replacement.uppercased() }
        guard original.first?.isUppercase == true else { return replacement }
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}
