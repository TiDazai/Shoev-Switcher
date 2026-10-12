import Foundation

/// Both modules use the same read-only SQLite connection and embedded corpus.
final class SpellLexicon: WordScoring {
    static let shared = SpellLexicon()
    private let cache = NSCache<NSString, NSNumber>()

    private init() { cache.countLimit = 10_000 }

    func score(for word: String, language: SpellLanguage) -> Int? {
        let key = "\(language.rawValue):\(word)" as NSString
        if let value = cache.object(forKey: key) { return value.intValue < 0 ? nil : value.intValue }
        let score = EmbeddedLexicon.shared.score(for: word,
            language: language == .english ? .english : .russian).map { Int(($0 * 100).rounded()) }
        cache.setObject(NSNumber(value: score ?? -1), forKey: key)
        return score
    }
}

protocol WordScoring: AnyObject {
    func score(for word: String, language: SpellLanguage) -> Int?
}
