import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

final class InputEngine: KeyboardMonitorDelegate {
    private let logger = Logger(subsystem: "com.shoev.switcher", category: "InputEngine")
    private let sourceManager: InputSourceManager
    private let detector: LanguageDetector
    private let ruleStore: RuleStore
    private let journalStore: JournalStore?
    private let injector: EventInjector
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

    init(
        sourceManager: InputSourceManager,
        detector: LanguageDetector,
        ruleStore: RuleStore,
        journalStore: JournalStore?,
        injector: EventInjector = EventInjector(),
        defaults: UserDefaults = .standard,
        selectionConverter: TextSelectionConverter = TextSelectionConverter(),
        correctionNotifier: CorrectionNotifier = CorrectionNotifier(),
        applicationProfiles: ApplicationLanguageProfileStore = ApplicationLanguageProfileStore()
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
        guard defaults.bool(forKey: PreferenceKey.enabled) else {
            resetAll()
            return false
        }

        let application = NSWorkspace.shared.frontmostApplication
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

        if keyCode == 51 {
            if defaults.bool(forKey: PreferenceKey.undoAutomaticCorrection),
               current.isEmpty,
               undoLastAutomaticCorrection(application: application) {
                return true
            }
            current.removeLast()
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
        defer { lastShortcutShiftRelease = now }
        if let previous = lastShortcutShiftRelease, now.timeIntervalSince(previous) <= 0.45 {
            performManualConversion()
            lastShortcutShiftRelease = nil
        }
    }

    private func completeCurrentToken(
        terminator: String,
        trailingEvent: CGEvent,
        application: NSRunningApplication?
    ) -> Bool {
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
            sourceManager.select(candidate.targetLanguage)
            injector.replace(
                deleteCount: original.count,
                with: candidate.replacement,
                trailingEvent: trailingEvent
            )
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
        let application = NSWorkspace.shared.frontmostApplication
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
            sourceManager.select(conversion.targetLanguage)
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
            sourceManager.select(targetLanguage)
            injector.replace(deleteCount: original.count, with: alternative)
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
        sourceManager.select(completed.alternativeLanguage)
        injector.replace(
            deleteCount: completed.displayedText.count + completed.terminator.count,
            with: completed.alternativeText + completed.terminator
        )
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

        sourceManager.select(completed.alternativeLanguage)
        injector.replace(
            deleteCount: completed.displayedText.count + completed.terminator.count,
            with: completed.alternativeText + completed.terminator
        )
        correctionNotifier.show(original: completed.displayedText, replacement: completed.alternativeText)
        log(
            kind: .undone,
            original: completed.displayedText,
            replacement: completed.alternativeText,
            sourceLanguage: completed.displayedLanguage,
            targetLanguage: completed.alternativeLanguage,
            application: application
        )
        if defaults.bool(forKey: PreferenceKey.rememberUndoneCorrections) {
            journalStore?.addRule(
                kind: .keep,
                pattern: completed.alternativeText,
                language: completed.alternativeLanguage
            ) { [weak self] in
                self?.reloadRules()
            }
        }
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
        if current.isEmpty { lastCompleted = nil }
        current.append(stroke)
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
    }

    private func recordToken(_ text: String, language: InputLanguage, terminator: String) {
        if defaults.bool(forKey: PreferenceKey.applicationContext) {
            applicationProfiles.observe(
                language,
                applicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
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
