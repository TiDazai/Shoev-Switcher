import AppKit
import CoreGraphics
import Foundation
import OSLog

final class SpellInputEngine: KeyboardMonitorDelegate {
    private let logger = Logger(subsystem: "com.shoev.spell", category: "input")
    private let corrector: SpellCorrectionEngine
    private let punctuator: RussianPunctuationEngine
    private let injector: SpellTextInjecting
    private let journal: SpellJournalStore
    private var word = ""
    private var phrase = ""
    private var activePID: pid_t?
    private let readCaret: () -> CaretContext?
    private let defaults: UserDefaults
    private let frontmost: () -> NSRunningApplication?
    private var knownPrefix: String?
    private var editingWord = false
    private var capitalizeWord = false
    private var expectedCaret: CaretContext?

    init(
        corrector: SpellCorrectionEngine = SpellCorrectionEngine(),
        punctuator: RussianPunctuationEngine = RussianPunctuationEngine(),
        injector: SpellTextInjecting = SpellTextInjector(),
        journal: SpellJournalStore = SpellJournalStore(),
        defaults: UserDefaults = .standard,
        readCaret: @escaping () -> CaretContext? = { CaretContextReader().read() },
        frontmost: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    ) {
        self.corrector = corrector
        self.punctuator = punctuator
        self.injector = injector
        self.journal = journal
        self.defaults = defaults
        self.readCaret = readCaret
        self.frontmost = frontmost
    }

    func keyboardMonitorDidResetInput(_ monitor: KeyboardMonitor) {
        if !phrase.isEmpty {
            logger.info("Input context reset externally; bufferedCharacters=\(self.phrase.count)")
        }
        reset()
    }

    func keyboardMonitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool {
        let app = frontmost()
        if activePID != app?.processIdentifier {
            logger.info("Frontmost application changed; bufferedCharacters=\(self.phrase.count)")
            activePID = app?.processIdentifier
            reset()
        }
        guard defaults.bool(forKey: SpellPreferenceKey.enabled), !isExcluded(app) else {
            reset(); return false
        }
        if event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty == false {
            logger.info("Input context reset by modifier; bufferedCharacters=\(self.phrase.count)")
            reset(); return false
        }
        if keyCode == 51 || keyCode == 117 {
            // Deletion can remove a selection, composed character or text outside
            // our buffer. Only start tracking again at a verified word boundary.
            reset()
            return false
        }
        // Sending a message, inserting a newline and moving focus are editor
        // actions. Preserve the physical event, including its modifier flags.
        if [36, 76, 48].contains(keyCode) || text == "\r" || text == "\n" || text == "\t" {
            reset()
            return false
        }
        if [123, 124, 125, 126, 115, 119, 116, 121].contains(keyCode) {
            logger.info("Input context reset by navigation; bufferedCharacters=\(self.phrase.count)")
            reset(); return false
        }
        guard !text.isEmpty else { reset(); return false }
        guard let caret = readCaret() else {
            reset()
            return false
        }
        do {
            if expectedCaret.map({ !caret.sameField(as: $0) }) == true
                || caret.selectionLength > 0 || (!phrase.isEmpty && !caret.prefix.hasSuffix(phrase)) {
                reset()
            }
            knownPrefix = caret.prefix
            expectedCaret = caret
            if phrase.isEmpty { editingWord = caret.startsInsideWord || caret.selectionLength > 0 }
        }
        if text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            if word.isEmpty {
                capitalizeWord = !editingWord && CapitalizationContext.shouldCapitalize(after: caret.prefix)
            }
            knownPrefix = knownPrefix.map { $0 + text }
            if !editingWord {
                word += text
                phrase += text
            }
            if phrase.count > 500 || word.count > 32 {
                reset()
                editingWord = true
            }
            // Never suppress a letter to insert a capital via Accessibility.
            // Some editors acknowledge the setter without inserting anything.
            return false
        }

        if text == " " {
            let result = finishSegment(trailingEvent: event, delimiter: text, endsSentence: false, application: app)
            editingWord = false
            return result
        }
        if text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: ",.;:!?…").contains($0) }) {
            let endsSentence = text.unicodeScalars.contains { CharacterSet(charactersIn: ".!?…").contains($0) }
            let result = finishSegment(trailingEvent: event, delimiter: text, endsSentence: endsSentence, application: app)
            editingWord = false
            return result
        }

        let prefix = knownPrefix
        reset()
        knownPrefix = prefix.map { $0 + text }
        return false
    }

    func keyboardMonitor(_ monitor: KeyboardMonitor, flagsChanged event: CGEvent, keyCode: CGKeyCode) {}

    private func isExcluded(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return defaults.stringArray(forKey: SpellPreferenceKey.excludedApplications)?.contains(id) == true
    }

    private func finishSegment(
        trailingEvent: CGEvent,
        delimiter: String,
        endsSentence: Bool,
        application: NSRunningApplication?
    ) -> Bool {
        let originalPhrase = phrase
        var replacement = phrase
        var correction: Correction?
        var replacementWord = word
        if !word.isEmpty,
           defaults.bool(forKey: SpellPreferenceKey.automaticCorrection),
           let found = corrector.correction(for: word) {
            replacementWord = found.replacement
            correction = found
        }
        if capitalizeWord, !editingWord, defaults.bool(forKey: SpellPreferenceKey.automaticCapitalization) {
            replacementWord = punctuator.capitalized(replacementWord)
        }
        if !word.isEmpty {
            replacement.removeLast(word.count)
            replacement += replacementWord
        }
        if let found = correction {
            correction = Correction(original: found.original, replacement: replacementWord)
        }
        capitalizeWord = false

        if defaults.bool(forKey: SpellPreferenceKey.automaticPunctuation) {
            let beforePunctuation = replacement
            replacement = punctuator.punctuate(replacement)
            logger.info("Punctuation evaluated; bufferedCharacters=\(originalPhrase.count), wordCharacters=\(self.word.count), changed=\(beforePunctuation != replacement)")
        }

        if replacement != originalPhrase {
            // Re-read after candidate lookup: focus/selection may have changed.
            guard let caret = readCaret(), caret.selectionLength == 0,
                  let expectedCaret, caret.matches(expectedCaret),
                  frontmost()?.processIdentifier == application?.processIdentifier,
                  caret.prefix == knownPrefix,
                  caret.prefix.hasSuffix(originalPhrase),
                  !originalPhrase.isEmpty else {
                SpellInputDiagnostics.shared.record(.contextChanged)
                reset(); return false
            }
            let edit = TextReplacement(original: originalPhrase, replacement: replacement)
            guard injector.replaceAfterDelimiter(deleteCount: edit.deleteCount, with: edit.text,
                trailingEvent: trailingEvent, context: caret, completion: { [weak self] in
                    guard let self else { return }
                    if let correction { self.journal.record(correction, application: application) }
                    // Recover phrase context only if no following word has
                    // started while the renderer acknowledged the edit.
                    if self.phrase.isEmpty, !endsSentence { self.phrase = replacement + delimiter }
                }) else {
                reset()
                return false
            }
            if endsSentence {
                reset()
            } else {
                phrase = replacement + delimiter
                word.removeAll(keepingCapacity: true)
            }
            return true
        }

        if let correction { journal.record(correction, application: application) }
        if endsSentence {
            reset()
        } else {
            phrase += delimiter
            word.removeAll(keepingCapacity: true)
        }
        return false
    }

    private func reset() {
        expectedCaret = nil
        knownPrefix = nil
        editingWord = false
        capitalizeWord = false
        word.removeAll(keepingCapacity: true)
        phrase.removeAll(keepingCapacity: true)
    }
}
