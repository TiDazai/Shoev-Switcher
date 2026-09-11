import Foundation

final class RuleStore: RuleProviding {
    private let lock = NSLock()
    private var rules: [UserRule] = []

    func replaceRules(_ newRules: [UserRule]) {
        lock.withLock { rules = newRules }
    }

    func decision(
        original: String,
        alternative: String,
        sourceLanguage: InputLanguage,
        applicationBundleIdentifier: String?
    ) -> DetectionDecision? {
        let normalized = Self.normalize(original)
        return lock.withLock {
            let matching = rules
                .filter { rule in
                    Self.normalize(rule.pattern) == normalized
                        && (rule.applicationBundleIdentifier == nil
                            || rule.applicationBundleIdentifier == applicationBundleIdentifier)
                        && (rule.language == nil || rule.language == sourceLanguage)
                }
                .sorted { lhs, rhs in
                    (lhs.applicationBundleIdentifier != nil ? 1 : 0)
                        > (rhs.applicationBundleIdentifier != nil ? 1 : 0)
                }

            guard let rule = matching.first else { return nil }
            switch rule.kind {
            case .keep, .accept:
                return .keep
            case .convert:
                let targetLanguage: InputLanguage = sourceLanguage == .english ? .russian : .english
                return .convert(ConversionCandidate(
                    original: original,
                    replacement: rule.replacement ?? alternative,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                ))
            }
        }
    }

    func isAccepted(_ word: String, language: InputLanguage) -> Bool {
        let normalized = Self.normalize(word)
        return lock.withLock {
            rules.contains { rule in
                rule.kind == .accept
                    && rule.language == language
                    && Self.normalize(rule.pattern) == normalized
            }
        }
    }

    private static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
