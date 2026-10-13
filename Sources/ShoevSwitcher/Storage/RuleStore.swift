import Foundation

final class RuleStore: RuleProviding {
    private let lock = NSLock()
    private var ruleIndex: [String: [UserRule]] = [:]
    private var wordIndex: [String: [PersonalWord]] = [:]

    func replaceRules(_ newRules: [UserRule]) {
        lock.withLock { ruleIndex = Dictionary(grouping: newRules, by: { Self.normalize($0.pattern) }) }
    }

    func replaceWords(_ newWords: [PersonalWord]) { lock.withLock { wordIndex = Dictionary(grouping: newWords, by: { $0.language.rawValue + ":" + Self.normalize($0.word) }) } }

    func replaceKnowledge(rules: [UserRule], words: [PersonalWord]) {
        lock.withLock {
            ruleIndex = Dictionary(grouping: rules, by: { Self.normalize($0.pattern) })
            wordIndex = Dictionary(grouping: words, by: { $0.language.rawValue + ":" + Self.normalize($0.word) })
        }
    }

    func personalSpellingScore(_ word: String, language: InputLanguage, application: String?) -> Int? {
        lock.withLock {
            (wordIndex[language.rawValue + ":" + Self.normalize(word)] ?? []).contains {
                $0.module != .switcher && ($0.applicationBundleIdentifier == nil || $0.applicationBundleIdentifier == application)
            } ? 500 : nil
        }
    }

    func decision(
        original: String,
        alternative: String,
        sourceLanguage: InputLanguage,
        applicationBundleIdentifier: String?
    ) -> DetectionDecision? {
        let normalized = Self.normalize(original)
        return lock.withLock {
            let matching = (ruleIndex[normalized] ?? [])
                .filter { rule in
                    rule.isEnabled && rule.module != .spell && Self.normalize(rule.pattern) == normalized
                        && (rule.applicationBundleIdentifier == nil
                            || rule.applicationBundleIdentifier == applicationBundleIdentifier)
                        && (rule.language == nil || rule.language == sourceLanguage)
                }
                .sorted { lhs, rhs in
                    if (lhs.origin == .learning) != (rhs.origin == .learning) { return lhs.origin != .learning }
                    return (lhs.applicationBundleIdentifier != nil ? 1 : 0)
                        > (rhs.applicationBundleIdentifier != nil ? 1 : 0)
                }

            guard let rule = matching.first else {
                return (wordIndex[sourceLanguage.rawValue + ":" + normalized] ?? []).contains { Self.normalize($0.word) == normalized && $0.language == sourceLanguage && $0.module != .spell
                    && ($0.applicationBundleIdentifier == nil || $0.applicationBundleIdentifier == applicationBundleIdentifier) } ? .keep : nil
            }
            switch rule.kind {
            case .keep, .accept:
                return .keep
            case .convert:
                let targetLanguage = rule.targetLanguage ?? (sourceLanguage == .english ? .russian : .english)
                return .convert(ConversionCandidate(
                    original: original,
                    replacement: Self.restoreCase(original, replacement: rule.replacement ?? alternative),
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                ))
            }
        }
    }

    func isAccepted(_ word: String, language: InputLanguage) -> Bool { isAccepted(word, language: language, application: nil) }

    func isAccepted(_ word: String, language: InputLanguage, application: String?) -> Bool {
        let normalized = Self.normalize(word)
        return lock.withLock {
            (wordIndex[language.rawValue + ":" + normalized] ?? []).contains { $0.language == language && $0.module != .spell && ($0.applicationBundleIdentifier == nil || $0.applicationBundleIdentifier == application) && Self.normalize($0.word) == normalized }
            || (ruleIndex[normalized] ?? []).contains { rule in
                rule.isEnabled && rule.kind == .accept && rule.module != .spell && (rule.applicationBundleIdentifier == nil || rule.applicationBundleIdentifier == application)
                    && rule.language == language
                    && Self.normalize(rule.pattern) == normalized
            }
        }
    }

    func spellingDecision(_ word: String, language: InputLanguage, application: String?) -> DetectionDecision? {
        let normalized = Self.normalize(word)
        return lock.withLock {
            let matching = (ruleIndex[normalized] ?? []).filter { $0.isEnabled && $0.module != .switcher && Self.normalize($0.pattern) == normalized
                && ($0.language == nil || $0.language == language)
                && ($0.applicationBundleIdentifier == nil || $0.applicationBundleIdentifier == application) }
                .sorted { a, b in
                    if (a.origin == .learning) != (b.origin == .learning) { return a.origin != .learning }
                    return a.applicationBundleIdentifier != nil && b.applicationBundleIdentifier == nil
                }
            if let rule = matching.first {
                if rule.kind != .convert { return .keep }
                guard rule.module == .spell || rule.targetLanguage == language,
                      let replacement = rule.replacement else { return nil }
                return .convert(ConversionCandidate(original: word, replacement: Self.restoreCase(word, replacement: replacement),
                    sourceLanguage: language, targetLanguage: language))
            }
            return (wordIndex[language.rawValue + ":" + normalized] ?? []).contains { $0.language == language && $0.module != .switcher && Self.normalize($0.word) == normalized
                && ($0.applicationBundleIdentifier == nil || $0.applicationBundleIdentifier == application) } ? .keep : nil
        }
    }

    private static func restoreCase(_ original: String, replacement: String) -> String {
        if original == original.uppercased() { return replacement.uppercased() }
        if original.first?.isUppercase == true { return replacement.prefix(1).uppercased() + replacement.dropFirst() }
        return replacement
    }

    private static func normalize(_ word: String) -> String {
        word.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
