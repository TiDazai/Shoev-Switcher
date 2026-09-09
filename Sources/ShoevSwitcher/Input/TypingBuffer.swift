import Foundation

struct TypingBuffer {
    private(set) var current = TypedToken()
    private(set) var lastCompleted: CompletedToken?

    mutating func append(_ stroke: KeyStroke) {
        current.append(stroke)
    }

    mutating func backspace() {
        current.removeLast()
        if current.isEmpty {
            lastCompleted = nil
        }
    }

    mutating func complete(
        displayedText: String,
        alternativeText: String,
        displayedLanguage: InputLanguage,
        alternativeLanguage: InputLanguage,
        terminator: String,
        processIdentifier: pid_t,
        at date: Date = Date()
    ) {
        lastCompleted = CompletedToken(
            displayedText: displayedText,
            alternativeText: alternativeText,
            displayedLanguage: displayedLanguage,
            alternativeLanguage: alternativeLanguage,
            terminator: terminator,
            processIdentifier: processIdentifier,
            completedAt: date
        )
        current.clear()
    }

    mutating func clearCurrent() {
        current.clear()
    }

    mutating func clearAll() {
        current.clear()
        lastCompleted = nil
    }
}
