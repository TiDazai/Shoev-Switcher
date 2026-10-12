import Foundation

final class SpellCorrectionEngine {
    private static let protectedWords: Set<String> = ["shoev"]
    private let lexicon: WordScoring
    private let defaults: UserDefaults

    init(lexicon: WordScoring = SpellLexicon.shared, defaults: UserDefaults = .standard) {
        self.lexicon = lexicon
        self.defaults = defaults
    }

    func correction(for original: String) -> Correction? {
        let normalized = original.lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard Self.protectedWords.contains(normalized) == false,
              original.allSatisfy({ $0.isLetter }),
              original == original.lowercased() || original == original.uppercased()
                || original == original.prefix(1).uppercased() + original.dropFirst().lowercased(),
              normalized.count >= defaults.integer(forKey: SpellPreferenceKey.minimumLength),
              normalized.count <= 32,
              let language = SpellLanguage.detect(in: normalized) else { return nil }
        let originalScore = lexicon.score(for: normalized, language: language)
        let minimumScore = defaults.integer(forKey: SpellPreferenceKey.minimumScore)
        if let originalScore, originalScore >= minimumScore { return nil }

        let candidates = editsAtDistanceOne(from: normalized, language: language)
            .compactMap { word -> SpellingCandidate? in
                guard let score = lexicon.score(for: word, language: language) else { return nil }
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
