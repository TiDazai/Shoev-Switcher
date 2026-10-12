import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

final class InputEngine: KeyboardMonitorDelegate {
    private let logger = Logger(subsystem: "com.shoev.switcher", category: "InputEngine")
    private let sourceManager: InputSourceManaging
    private let detector: LanguageDetector
    private let ruleStore: RuleStore
    private let journalStore: JournalStore?
    private let injector: TextReplacing
    private let defaults: UserDefaults
    private let selectionConverter: TextSelectionConverter
    private let correctionNotifier: CorrectionNotifier
    private let applicationProfiles: ApplicationLanguageProfileStore
    private let sensitiveInputGuard = SensitiveInputGuard()

    private var current = TypedToken()
    private var lastCompleted: CompletedToken?
    private var recentLanguages: [InputLanguage] = []
    private var recentTokens: [ContextToken] = []
    private var activeProcessIdentifier: pid_t?
    private var shortcutShiftWasDown = false
    private var lastShortcutShiftRelease: Date?
    private var tokenStart: TextReplacementContext?
    private var completedField: AXUIElement?
    private var completedPrefix: String?
    private let readContext: () -> TextReplacementContext?
    private let frontmost: () -> NSRunningApplication?

    init(
        sourceManager: InputSourceManaging,
        detector: LanguageDetector,
        ruleStore: RuleStore,
        journalStore: JournalStore?,
        injector: TextReplacing = EventInjector(),
        defaults: UserDefaults = .standard,
        selectionConverter: TextSelectionConverter = TextSelectionConverter(),
        correctionNotifier: CorrectionNotifier = CorrectionNotifier(),
        applicationProfiles: ApplicationLanguageProfileStore = ApplicationLanguageProfileStore(),
        readContext: @escaping () -> TextReplacementContext? = { TextReplacementContextReader().read() },
        frontmost: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    ) {
        self.sourceManager = sourceManager
        self.detector = detector
        self.ruleStore = ruleStore
        self.journalStore = journalStore
        self.injector = injector
        self.defaults = defaults
        self.selectionConverter = selectionConverter
        self.correctionNotifier = correctionNotifier
        self.applicationProfiles = applicationProfiles
        self.readContext = readContext
        self.frontmost = frontmost
    }

    func reloadRules() {
        guard let journalStore else { return }
        ruleStore.replaceRules(journalStore.loadRules())
    }

    func keyboardMonitorDidResetInput(_ monitor: KeyboardMonitor) {
        sensitiveInputGuard.reset()
        resetAll()
    }

    func keyboardMonitor(
        _ monitor: KeyboardMonitor,
        keyDown event: CGEvent,
        text: String,
        keyCode: CGKeyCode
    ) -> Bool {
        lastShortcutShiftRelease = nil
        shortcutShiftWasDown = false
        guard defaults.bool(forKey: PreferenceKey.enabled) else {
            resetAll()
            return false
        }

        let application = frontmost()
        if activeProcessIdentifier != application?.processIdentifier {
            sensitiveInputGuard.reset()
            resetAll()
            activeProcessIdentifier = application?.processIdentifier
        }
        guard !isExcluded(application) else {
            resetAll()
            return false
        }
        guard !sensitiveInputGuard.isSensitive(processIdentifier: application?.processIdentifier) else {
            resetAll()
            return false
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            resetAll()
            return false
        }

        // Never replay Enter/Tab: editors decide whether the physical key sends
        // a message, starts a paragraph or moves focus (including Shift+Enter).
        if [36, 76, 48].contains(keyCode) || text == "\r" || text == "\n" || text == "\t" {
            resetAll()
            return false
        }
        if keyCode == 51 {
            if defaults.bool(forKey: PreferenceKey.undoAutomaticCorrection),
               current.isEmpty,
               undoLastAutomaticCorrection(application: application) {
                return true
            }
            resetAll()
            return false
        }
        if navigationKeyCodes.contains(keyCode) {
            resetAll()
            return false
        }
        guard !text.isEmpty else { return false }

        let shiftPressed = flags.contains(.maskShift)
        let capsLockEnabled = flags.contains(.maskAlphaShift)
        let stroke = KeyStroke(
            keyCode: keyCode,
            visibleText: text,
            shouldUppercase: shiftPressed != capsLockEnabled
        )
        if isLetterText(text) || (isWordJoiner(text) && !current.isEmpty) {
            append(stroke)
            return false
        }

        if sourceManager.isPotentialWordStroke(stroke) {
            if shouldUsePotentialLetterAsTerminator(text) {
                return completeCurrentToken(
                    terminator: text,
                    trailingEvent: event,
                    application: application
                )
            }
            append(stroke)
            return false
        }

        guard !current.isEmpty else { return false }
        return completeCurrentToken(terminator: text, trailingEvent: event, application: application)
    }

    func keyboardMonitor(_ monitor: KeyboardMonitor, flagsChanged event: CGEvent, keyCode: CGKeyCode) {
        let shortcut = ManualShortcut(
            rawValue: defaults.string(forKey: PreferenceKey.manualShortcut) ?? ""
        ) ?? .rightShift
        guard defaults.bool(forKey: PreferenceKey.manualConversion), keyCode == shortcut.keyCode else { return }
        let isDown = event.flags.contains(.maskShift)
        if isDown {
            shortcutShiftWasDown = true
            return
        }
        guard shortcutShiftWasDown else { return }
        shortcutShiftWasDown = false

        let now = Date()
        if let previous = lastShortcutShiftRelease, now.timeIntervalSince(previous) <= 0.45 {
            performManualConversion()
            lastShortcutShiftRelease = nil
        } else { lastShortcutShiftRelease = now }
    }

    private func completeCurrentToken(
        terminator: String,
        trailingEvent: CGEvent,
        application: NSRunningApplication?
    ) -> Bool {
        guard let context = verifiedCurrentContext() else { resetAll(); return false }
        guard let sourceLanguage = sourceManager.currentLanguage() else {
            logger.error("Token ignored because the active input language is unknown")
            current.clear()
            return false
        }
        let targetLanguage: InputLanguage = sourceLanguage == .english ? .russian : .english
        let original = current.visibleText
        guard let alternative = sourceManager.text(for: current.strokes, in: targetLanguage),
              alternative != original else {
            logger.info(
                "Token kept before detection. length=\(original.count, privacy: .public) source=\(sourceLanguage.rawValue, privacy: .public)"
            )
            current.clear()
            return false
        }

        let pid = application?.processIdentifier ?? 0
        let shouldAutomaticallyCorrect = defaults.bool(forKey: PreferenceKey.automaticCorrection)
        let evaluation = shouldAutomaticallyCorrect
            ? detector.evaluate(
                original: original,
                alternative: alternative,
                sourceLanguage: sourceLanguage,
                applicationBundleIdentifier: application?.bundleIdentifier,
                context: DetectionContext(
                    recentLanguages: defaults.bool(forKey: PreferenceKey.phraseContext) ? recentLanguages : [],
                    recentTokens: defaults.bool(forKey: PreferenceKey.phraseContext) ? recentTokens : [],
                    applicationLanguage: defaults.bool(forKey: PreferenceKey.applicationContext)
                        ? applicationProfiles.preferredLanguage(for: application?.bundleIdentifier)
                        : nil
                )
            )
            : DetectionEvaluation(decision: .keep, likelyLanguage: sourceLanguage)

        switch evaluation.decision {
        case .keep:
            completedField = context.element
            completedPrefix = context.prefix + terminator
            logger.info(
                "Detector kept token. length=\(original.count, privacy: .public) source=\(sourceLanguage.rawValue, privacy: .public)"
            )
            lastCompleted = CompletedToken(
                displayedText: original,
                alternativeText: alternative,
                displayedLanguage: sourceLanguage,
                alternativeLanguage: targetLanguage,
                terminator: terminator,
                processIdentifier: pid,
                completedAt: Date(),
                correctionKind: nil
            )
            logTypedIfNeeded(original, language: sourceLanguage, application: application)
            let contextText = evaluation.likelyLanguage == sourceLanguage ? original : alternative
            recordToken(contextText, language: evaluation.likelyLanguage, terminator: terminator)
            current.clear()
            return false

        case .convert(let candidate):
            logger.info(
                "Detector converted token. length=\(original.count, privacy: .public) source=\(sourceLanguage.rawValue, privacy: .public)"
            )
            guard injector.replace(
                original: original,
                with: candidate.replacement,
                trailingEvent: trailingEvent,
                context: context
            ) else { resetAll(); return false }
            _ = sourceManager.select(candidate.targetLanguage)
            completedField = context.element
            completedPrefix = String(context.prefix.dropLast(original.count)) + candidate.replacement + terminator
            correctionNotifier.show(original: candidate.original, replacement: candidate.replacement)
            lastCompleted = CompletedToken(
                displayedText: candidate.replacement,
                alternativeText: candidate.original,
                displayedLanguage: candidate.targetLanguage,
                alternativeLanguage: candidate.sourceLanguage,
                terminator: terminator,
                processIdentifier: pid,
                completedAt: Date(),
                correctionKind: .correction
            )
            log(
                kind: .correction,
                original: candidate.original,
                replacement: candidate.replacement,
                sourceLanguage: candidate.sourceLanguage,
                targetLanguage: candidate.targetLanguage,
                application: application
            )
            recordToken(candidate.replacement, language: candidate.targetLanguage, terminator: terminator)
            current.clear()
            return true
        }
    }

    private func performManualConversion() {
        let application = frontmost()
        let pid = application?.processIdentifier ?? 0

        guard defaults.bool(forKey: PreferenceKey.enabled),
              !isExcluded(application),
              !sensitiveInputGuard.isSensitive(processIdentifier: application?.processIdentifier) else {
            return
        }

        if let sourceLanguage = sourceManager.currentLanguage(),
           let conversion = selectionConverter.convertSelection(
               sourceLanguage: sourceLanguage,
               sourceManager: sourceManager,
               injector: injector
           ) {
            _ = sourceManager.select(conversion.targetLanguage)
            correctionNotifier.show(original: conversion.original, replacement: conversion.replacement)
            log(
                kind: .manualCorrection,
                original: conversion.original,
                replacement: conversion.replacement,
                sourceLanguage: conversion.sourceLanguage,
                targetLanguage: conversion.targetLanguage,
                application: application
            )
            if defaults.bool(forKey: PreferenceKey.applicationContext) {
                applicationProfiles.observe(
                    conversion.targetLanguage,
                    applicationBundleIdentifier: application?.bundleIdentifier
                )
            }
            resetAll()
            return
        }

        if !current.isEmpty,
           let sourceLanguage = sourceManager.currentLanguage() {
            let targetLanguage: InputLanguage = sourceLanguage == .english ? .russian : .english
            let original = current.visibleText
            guard let alternative = sourceManager.text(for: current.strokes, in: targetLanguage),
                  alternative != original else { return }
            guard let context = verifiedCurrentContext(),
                  injector.replace(original: original, with: alternative, trailingEvent: nil, context: context) else { resetAll(); return }
            _ = sourceManager.select(targetLanguage)
            completedField = context.element
            completedPrefix = String(context.prefix.dropLast(original.count)) + alternative
            correctionNotifier.show(original: original, replacement: alternative)
            lastCompleted = CompletedToken(
                displayedText: alternative,
                alternativeText: original,
                displayedLanguage: targetLanguage,
                alternativeLanguage: sourceLanguage,
                terminator: "",
                processIdentifier: pid,
                completedAt: Date(),
                correctionKind: .manualCorrection
            )
            log(
                kind: .manualCorrection,
                original: original,
                replacement: alternative,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                application: application
            )
            recordManualLearning(candidateOriginal: original, replacement: alternative, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            recordToken(alternative, language: targetLanguage, terminator: "")
            current.clear()
            return
        }

        guard let completed = lastCompleted,
              completed.processIdentifier == pid,
              Date().timeIntervalSince(completed.completedAt) <= 8 else { return }
        if completed.correctionKind == .correction {
            _ = undoLastAutomaticCorrection(application: application)
            return
        }
        guard let context = verifiedCompletedContext(),
              injector.replace(original: completed.displayedText + completed.terminator,
                with: completed.alternativeText + completed.terminator, trailingEvent: nil, context: context) else { resetAll(); return }
        _ = sourceManager.select(completed.alternativeLanguage)
        completedPrefix = String(context.prefix.dropLast(completed.displayedText.count + completed.terminator.count))
            + completed.alternativeText + completed.terminator
        correctionNotifier.show(original: completed.displayedText, replacement: completed.alternativeText)
        log(
            kind: .manualCorrection,
            original: completed.displayedText,
            replacement: completed.alternativeText,
            sourceLanguage: completed.displayedLanguage,
            targetLanguage: completed.alternativeLanguage,
            application: application
        )
        if completed.correctionKind == nil {
            recordManualLearning(
                candidateOriginal: completed.displayedText,
                replacement: completed.alternativeText,
                sourceLanguage: completed.displayedLanguage,
                targetLanguage: completed.alternativeLanguage
            )
        }
        if !recentLanguages.isEmpty { recentLanguages.removeLast() }
        if !recentTokens.isEmpty { recentTokens.removeLast() }
        recordToken(
            completed.alternativeText,
            language: completed.alternativeLanguage,
            terminator: completed.terminator
        )
        lastCompleted = CompletedToken(
            displayedText: completed.alternativeText,
            alternativeText: completed.displayedText,
            displayedLanguage: completed.alternativeLanguage,
            alternativeLanguage: completed.displayedLanguage,
            terminator: completed.terminator,
            processIdentifier: pid,
            completedAt: Date(),
            correctionKind: .manualCorrection
        )
    }

    private func undoLastAutomaticCorrection(application: NSRunningApplication?) -> Bool {
        let pid = application?.processIdentifier ?? 0
        guard defaults.bool(forKey: PreferenceKey.undoAutomaticCorrection),
              let completed = lastCompleted,
              completed.correctionKind == .correction,
              completed.processIdentifier == pid,
              Date().timeIntervalSince(completed.completedAt) <= 5 else { return false }

        guard let context = verifiedCompletedContext(),
              injector.replace(original: completed.displayedText + completed.terminator,
                with: completed.alternativeText + completed.terminator, trailingEvent: nil, context: context) else { resetAll(); return false }
        _ = sourceManager.select(completed.alternativeLanguage)
        correctionNotifier.show(original: completed.displayedText, replacement: completed.alternativeText)
        log(
            kind: .undone,
            original: completed.displayedText,
            replacement: completed.alternativeText,
            sourceLanguage: completed.displayedLanguage,
            targetLanguage: completed.alternativeLanguage,
            application: application
        )
        lastCompleted = nil
        if !recentLanguages.isEmpty { recentLanguages.removeLast() }
        if !recentTokens.isEmpty { recentTokens.removeLast() }
        recordToken(
            completed.alternativeText,
            language: completed.alternativeLanguage,
            terminator: completed.terminator
        )
        return true
    }

    private func recordManualLearning(
        candidateOriginal: String,
        replacement: String,
        sourceLanguage: InputLanguage,
        targetLanguage: InputLanguage
    ) {
        guard defaults.bool(forKey: PreferenceKey.automaticLearning) else { return }
        journalStore?.recordManualConversion(
            original: candidateOriginal,
            replacement: replacement,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) { [weak self] learned in
            if learned { self?.reloadRules() }
        }
    }

    private func isLetterText(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }

    private func append(_ stroke: KeyStroke) {
        if current.isEmpty {
            lastCompleted = nil
            guard let context = readContext(), context.range.length == 0, !context.startsInsideWord else { return }
            tokenStart = context
        }
        current.append(stroke)
        if current.strokes.count > 64 { resetAll() }
    }

    private func verifiedCurrentContext() -> TextReplacementContext? {
        guard let start = tokenStart, let context = readContext(), context.range.length == 0,
              CFEqual(start.element, context.element),
              context.prefix == start.prefix + current.visibleText else { return nil }
        return context
    }

    private func verifiedCompletedContext() -> TextReplacementContext? {
        guard let field = completedField, let prefix = completedPrefix, let context = readContext(),
              CFEqual(field, context.element), context.range.length == 0, context.prefix == prefix else { return nil }
        return context
    }

    private func isWordJoiner(_ text: String) -> Bool {
        text == "'" || text == "’" || text == "-"
    }

    private func shouldUsePotentialLetterAsTerminator(_ text: String) -> Bool {
        guard !current.isEmpty,
              punctuationCharacters.contains(text),
              let language = sourceManager.currentLanguage() else { return false }
        return detector.isKnown(current.visibleText, language: language)
    }

    private func isExcluded(_ application: NSRunningApplication?) -> Bool {
        guard let identifier = application?.bundleIdentifier else { return false }
        let exclusions = defaults.stringArray(forKey: PreferenceKey.excludedApplications) ?? []
        return exclusions.contains(identifier)
    }

    private func logTypedIfNeeded(
        _ text: String,
        language: InputLanguage,
        application: NSRunningApplication?
    ) {
        guard defaults.bool(forKey: PreferenceKey.fullDiaryEnabled) else { return }
        log(
            kind: .typed,
            original: text,
            replacement: nil,
            sourceLanguage: language,
            targetLanguage: nil,
            application: application
        )
    }

    private func log(
        kind: JournalEventKind,
        original: String,
        replacement: String?,
        sourceLanguage: InputLanguage?,
        targetLanguage: InputLanguage?,
        application: NSRunningApplication?
    ) {
        guard defaults.bool(forKey: PreferenceKey.journalEnabled) else { return }
        journalStore?.enqueue(JournalEntry(
            id: 0,
            createdAt: Date(),
            applicationBundleIdentifier: application?.bundleIdentifier,
            applicationName: application?.localizedName,
            original: original,
            replacement: replacement,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            kind: kind
        ))
    }

    private func resetAll() {
        current.clear()
        lastCompleted = nil
        recentLanguages.removeAll(keepingCapacity: true)
        recentTokens.removeAll(keepingCapacity: true)
        tokenStart = nil
        completedField = nil
        completedPrefix = nil
        shortcutShiftWasDown = false
        lastShortcutShiftRelease = nil
    }

    private func recordToken(_ text: String, language: InputLanguage, terminator: String) {
        if defaults.bool(forKey: PreferenceKey.applicationContext) {
            applicationProfiles.observe(
                language,
                applicationBundleIdentifier: frontmost()?.bundleIdentifier
            )
        }
        recentLanguages.append(language)
        recentTokens.append(ContextToken(text: text, language: language))
        if recentLanguages.count > 5 {
            recentLanguages.removeFirst(recentLanguages.count - 5)
        }
        if recentTokens.count > 5 {
            recentTokens.removeFirst(recentTokens.count - 5)
        }

        let sentenceTerminators = CharacterSet(charactersIn: ".!?\n\r")
        if terminator.unicodeScalars.contains(where: sentenceTerminators.contains) {
            recentLanguages.removeAll(keepingCapacity: true)
            recentTokens.removeAll(keepingCapacity: true)
        }
    }

    private let navigationKeyCodes: Set<CGKeyCode> = [53, 115, 116, 117, 119, 121, 123, 124, 125, 126]
    private let punctuationCharacters: Set<String> = [".", ",", ";", ":", "!", "?", "[", "]", "{", "}", "(", ")"]
}
