import Foundation

final class PhraseLexicon {
    static let shared = PhraseLexicon()

    private var phrases: [InputLanguage: Set<String>] = [:]

    private init() {
        guard let url = Bundle.module.url(forResource: "phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return
        }
        for language in InputLanguage.allCases {
            phrases[language] = Set((decoded[language.rawValue] ?? []).map(Self.normalize))
        }
    }

    func bonus(for words: [String], language: InputLanguage) -> Double {
        guard let phrases = phrases[language], words.count >= 2 else { return 0 }
        let normalized = words.map(Self.normalize)
        if normalized.count >= 3,
           phrases.contains(normalized.suffix(3).joined(separator: " ")) {
            return 1.35
        }
        if phrases.contains(normalized.suffix(2).joined(separator: " ")) {
            return 0.85
        }
        return 0
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
