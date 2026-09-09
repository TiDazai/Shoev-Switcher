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

    private var current = TypedToken()
    private var lastCompleted: CompletedToken?
    private var recentLanguages: [InputLanguage] = []
    private var activeProcessIdentifier: pid_t?
    private var rightShiftWasDown = false
    private var lastRightShiftRelease: Date?

    init(
        sourceManager: InputSourceManager,
        detector: LanguageDetector,
        ruleStore: RuleStore,
        journalStore: JournalStore?,
        injector: EventInjector = EventInjector(),
        defaults: UserDefaults = .standard
    ) {
        self.sourceManager = sourceManager
        self.detector = detector
        self.ruleStore = ruleStore
        self.journalStore = journalStore
        self.injector = injector
        self.defaults = defaults
    }

    func reloadRules() {
        guard let journalStore else { return }
        ruleStore.replaceRules(journalStore.loadRules())
    }

    func keyboardMonitorDidResetInput(_ monitor: KeyboardMonitor) {
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
            resetAll()
            activeProcessIdentifier = application?.processIdentifier
        }
        guard !isExcluded(application) else {
            resetAll()
            return false
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            current.clear()
            return false
        }

        if keyCode == 51 {
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
        if isWordText(text) || sourceManager.isPotentialWordStroke(stroke) {
            current.append(stroke)
            return false
        }

        guard !current.isEmpty else { return false }
        return completeCurrentToken(terminator: text, trailingEvent: event, application: application)
    }

    func keyboardMonitor(_ monitor: KeyboardMonitor, flagsChanged event: CGEvent, keyCode: CGKeyCode) {
        guard keyCode == 60 else { return }
        let isDown = event.flags.contains(.maskShift)
        if isDown {
            rightShiftWasDown = true
            return
        }
        guard rightShiftWasDown else { return }
        rightShiftWasDown = false

        let now = Date()
        defer { lastRightShiftRelease = now }
        if let previous = lastRightShiftRelease, now.timeIntervalSince(previous) <= 0.45 {
            performManualConversion()
            lastRightShiftRelease = nil
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
                context: DetectionContext(recentLanguages: recentLanguages)
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
                completedAt: Date()
            )
            logTypedIfNeeded(original, language: sourceLanguage, application: application)
            recordLanguage(evaluation.likelyLanguage, terminator: terminator)
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
            lastCompleted = CompletedToken(
                displayedText: candidate.replacement,
                alternativeText: candidate.original,
                displayedLanguage: candidate.targetLanguage,
                alternativeLanguage: candidate.sourceLanguage,
                terminator: terminator,
                processIdentifier: pid,
                completedAt: Date()
            )
            log(
                kind: .correction,
                original: candidate.original,
                replacement: candidate.replacement,
                sourceLanguage: candidate.sourceLanguage,
                targetLanguage: candidate.targetLanguage,
                application: application
            )
            recordLanguage(candidate.targetLanguage, terminator: terminator)
            current.clear()
            return true
        }
    }

    private func performManualConversion() {
        let application = NSWorkspace.shared.frontmostApplication
        let pid = application?.processIdentifier ?? 0

        if !current.isEmpty,
           let sourceLanguage = sourceManager.currentLanguage() {
            let targetLanguage: InputLanguage = sourceLanguage == .english ? .russian : .english
            let original = current.visibleText
            guard let alternative = sourceManager.text(for: current.strokes, in: targetLanguage),
                  alternative != original else { return }
            sourceManager.select(targetLanguage)
            injector.replace(deleteCount: original.count, with: alternative)
            lastCompleted = CompletedToken(
                displayedText: alternative,
                alternativeText: original,
                displayedLanguage: targetLanguage,
                alternativeLanguage: sourceLanguage,
                terminator: "",
                processIdentifier: pid,
                completedAt: Date()
            )
            log(
                kind: .manualCorrection,
                original: original,
                replacement: alternative,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                application: application
            )
            current.clear()
            return
        }

        guard let completed = lastCompleted,
              completed.processIdentifier == pid,
              Date().timeIntervalSince(completed.completedAt) <= 8 else { return }
        sourceManager.select(completed.alternativeLanguage)
        injector.replace(
            deleteCount: completed.displayedText.count + completed.terminator.count,
            with: completed.alternativeText + completed.terminator
        )
        log(
            kind: .manualCorrection,
            original: completed.displayedText,
            replacement: completed.alternativeText,
            sourceLanguage: completed.displayedLanguage,
            targetLanguage: completed.alternativeLanguage,
            application: application
        )
        lastCompleted = CompletedToken(
            displayedText: completed.alternativeText,
            alternativeText: completed.displayedText,
            displayedLanguage: completed.alternativeLanguage,
            alternativeLanguage: completed.displayedLanguage,
            terminator: completed.terminator,
            processIdentifier: pid,
            completedAt: Date()
        )
    }

    private func isWordText(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar) || scalar == "'" || scalar == "-"
        }
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
    }

    private func recordLanguage(_ language: InputLanguage, terminator: String) {
        recentLanguages.append(language)
        if recentLanguages.count > 5 {
            recentLanguages.removeFirst(recentLanguages.count - 5)
        }

        let sentenceTerminators = CharacterSet(charactersIn: ".!?\n\r")
        if terminator.unicodeScalars.contains(where: sentenceTerminators.contains) {
            recentLanguages.removeAll(keepingCapacity: true)
        }
    }

    private let navigationKeyCodes: Set<CGKeyCode> = [53, 115, 116, 117, 119, 121, 123, 124, 125, 126]
}
