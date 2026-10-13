import AppKit
import Carbon.HIToolbox

/// A bounded, local confirmation stage shared by both modules. Silence and an
/// automatic correction are not evidence that a personal rule is correct.
final class AdaptiveLearningController {
    private struct Pending {
        var entry: JournalEntry
        let element: AXUIElement
        let textOffset: Int
        let selectionTransport: TextSelectionTransport
        let prefix: String
        let module: CorrectionModule
        let startedAt: Date
        let proofKind: RuleKind?
        let journaled: Bool
        var boundaries = 0
    }
    private struct Repair {
        let pending: Pending
        let before: String
        let expiresAt: Date
    }
    private var pending: [String: Pending] = [:]
    private var repairs: [Repair] = []
    private let store: JournalStore?
    private let defaults: UserDefaults
    private let readContext: () -> TextReplacementContext?
    private let application: () -> String?
    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let rulesChanged: () -> Void
    private let outcomeObserver: (String, FeedbackOutcome) -> Void
    private let proofObserver: (LearningProof) -> Void
    private let secureInput: () -> Bool
    private var verificationScheduled = false
    private var queuedBoundary = false
    private var queuedUndo = false
    private var generation = 0

    init(store: JournalStore?, defaults: UserDefaults = .standard,
         readContext: @escaping () -> TextReplacementContext? = { TextReplacementContextReader().read() },
         application: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
         now: @escaping () -> Date = Date.init,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }, rulesChanged: @escaping () -> Void = {},
         outcomeObserver: @escaping (String, FeedbackOutcome) -> Void = { _, _ in },
         proofObserver: @escaping (LearningProof) -> Void = { _ in },
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() }) {
        self.store = store; self.defaults = defaults; self.readContext = readContext
        self.application = application; self.now = now; self.schedule = schedule
        self.rulesChanged = rulesChanged; self.outcomeObserver = outcomeObserver; self.proofObserver = proofObserver
        self.secureInput = secureInput
    }

    var pendingCount: Int { pending.count }

    func record(_ value: JournalEntry, module: CorrectionModule, journalEnabled: Bool, expectedPrefix: String? = nil) {
        guard journalEnabled || defaults.bool(forKey: PreferenceKey.automaticLearning) else { return }
        guard !secureInput() else { return }
        var entry = value
        entry.eventID = entry.eventID ?? UUID().uuidString
        if entry.kind == .typed {
            if journalEnabled { store?.enqueue(entry) }
            return
        }
        if entry.kind == .undone {
            handleExplicitUndo(entry, module: module)
            entry.outcome = .rejected
            if journalEnabled { store?.enqueue(entry) }
            return
        }
        guard let replacement = entry.replacement, !replacement.isEmpty,
              let context = safeContext(), context.range.length == 0,
              entry.applicationBundleIdentifier != nil, entry.applicationBundleIdentifier == application() else {
            entry.outcome = .unverified
            if journalEnabled { store?.enqueue(entry) }
            return
        }
        let prefix = expectedPrefix ?? context.prefix
        guard prefix.utf16.count <= 16_384, context.text.hasPrefix(prefix),
              prefix.range(of: replacement, options: .backwards) != nil else {
            entry.outcome = .unverified
            if journalEnabled { store?.enqueue(entry) }; return
        }
        entry.outcome = .pending
        if journalEnabled { store?.enqueue(entry) }
        add(Pending(entry: entry, element: context.element, textOffset: context.textOffset,
            selectionTransport: context.selectionTransport, prefix: prefix, module: module,
            startedAt: now(), proofKind: entry.kind == .manualCorrection ? .convert : nil, journaled: journalEnabled))
    }

    private func add(_ item: Pending) {
        if pending.count >= 8, let oldest = pending.min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
            finish(oldest, outcome: .unverified)
        }
        let id = item.entry.eventID!
        pending[id] = item
        let epoch = generation
        schedule(2) { [weak self] in
            guard let self, self.generation == epoch else { return }
            self.evaluate(context: self.safeContext(), boundary: false)
        }
        schedule(45) { [weak self] in
            guard let self, self.generation == epoch, self.pending[id] != nil else { return }
            self.finish(id, outcome: .unverified)
        }
    }

    /// Reads only while awaiting a confirmation. Physical keys are never
    /// consumed; verification happens after their normal delivery to the editor.
    func observe(event: CGEvent, text: String, keyCode: CGKeyCode) {
        guard !pending.isEmpty || !repairs.isEmpty else { return }
        guard !secureInput() else { cancelAll(); return }
        if [123, 124, 125, 126, 115, 119, 116, 121].contains(Int(keyCode)) { cancelAll(); return }
        let undo = event.flags.contains(.maskCommand) && !event.flags.contains(.maskShift) && keyCode == 6
        let submit = [36, 76].contains(Int(keyCode)) && event.flags.intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate]).isEmpty
        if submit { evaluate(context: safeContext(), boundary: true, submitted: true); return }
        let boundary = text == " " || text.unicodeScalars.contains { ".,!?;:".unicodeScalars.contains($0) }
        queuedBoundary = queuedBoundary || boundary
        queuedUndo = queuedUndo || undo
        guard !verificationScheduled else { return }
        verificationScheduled = true
        let epoch = generation
        schedule(0.015) { [weak self] in
            guard let self, self.generation == epoch else { return }
            self.verificationScheduled = false
            let boundary = self.queuedBoundary; let undo = self.queuedUndo
            self.queuedBoundary = false; self.queuedUndo = false
            self.evaluate(context: self.safeContext(), boundary: boundary, undoRequested: undo)
        }
    }

    func evaluate(context: TextReplacementContext?, boundary: Bool, submitted: Bool = false, undoRequested: Bool = false) {
        guard !secureInput() else { cancelAll(); return }
        guard let context else {
            for id in Array(pending.keys) { finish(id, outcome: .unverified) }
            repairs.removeAll(); return
        }
        repairs.removeAll { $0.expiresAt < now() }
        if boundary { evaluateRepairs(context) }
        for id in Array(pending.keys) {
            guard var item = pending[id] else { continue }
            guard item.entry.applicationBundleIdentifier == application(), sameRegion(item, context) else {
                finish(id, outcome: .unverified); continue
            }
            if undoRequested, let restored = restoredPrefix(item), context.text.hasPrefix(restored) {
                finish(id, outcome: .rejected)
                suspend(item)
                beginKeep(item, prefix: restored, context: context)
                continue
            }
            guard context.text.hasPrefix(item.prefix) else {
                finish(id, outcome: .edited)
                if let replacement = item.entry.replacement,
                   let range = item.prefix.range(of: replacement, options: .backwards) {
                    repairs.append(Repair(pending: item, before: String(item.prefix[..<range.lowerBound]), expiresAt: now().addingTimeInterval(12)))
                    if repairs.count > 8 { repairs.removeFirst(repairs.count - 8) }
                    schedule(12) { [weak self] in
                        guard let self else { return }
                        self.repairs.removeAll { $0.expiresAt <= self.now() }
                    }
                }
                continue
            }
            if boundary, context.range.length == 0, context.prefix.hasPrefix(item.prefix) {
                let tail = String(context.prefix.dropFirst(item.prefix.count))
                var words = tail.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
                if tail.last?.isLetter == true || tail.last?.isNumber == true { words = max(0, words - 1) }
                item.boundaries = max(item.boundaries, words)
            }
            pending[id] = item
            if submitted || (item.boundaries >= 2 && now().timeIntervalSince(item.startedAt) >= 2) {
                finish(id, outcome: .accepted)
                if let kind = item.proofKind { learn(item, kind: kind) }
            }
        }
    }

    func cancelAll() {
        generation &+= 1
        verificationScheduled = false; queuedBoundary = false; queuedUndo = false
        for id in Array(pending.keys) { finish(id, outcome: .unverified) }
        repairs.removeAll()
    }

    private func finish(_ id: String, outcome: FeedbackOutcome) {
        guard let item = pending.removeValue(forKey: id) else { return }
        if item.journaled { store?.resolveOutcome(eventID: id, outcome: outcome) }
        outcomeObserver(id, outcome)
    }

    private func handleExplicitUndo(_ undo: JournalEntry, module: CorrectionModule) {
        guard let item = pending.values.filter({ $0.module == module && $0.entry.applicationBundleIdentifier == undo.applicationBundleIdentifier
            && $0.entry.replacement == undo.original && $0.entry.original == undo.replacement }).max(by: { $0.startedAt < $1.startedAt }),
              let context = safeContext(), sameRegion(item, context),
              let restored = restoredPrefix(item), context.text.hasPrefix(restored) else { return }
        finish(item.entry.eventID!, outcome: .rejected)
        suspend(item)
        beginKeep(item, prefix: restored, context: context)
    }

    private func restoredPrefix(_ item: Pending) -> String? {
        guard let replacement = item.entry.replacement, let range = item.prefix.range(of: replacement, options: .backwards) else { return nil }
        return item.prefix.replacingCharacters(in: range, with: item.entry.original)
    }

    private func beginKeep(_ item: Pending, prefix: String, context: TextReplacementContext) {
        guard let language = item.entry.sourceLanguage,
              PersonalWordValidation.normalized(item.entry.original, language: language) != nil else { return }
        let entry = JournalEntry(id: 0, createdAt: now(), applicationBundleIdentifier: item.entry.applicationBundleIdentifier,
            applicationName: item.entry.applicationName, original: item.entry.original, replacement: nil,
            sourceLanguage: language, targetLanguage: language, kind: .manualCorrection, eventID: UUID().uuidString)
        add(Pending(entry: entry, element: context.element, textOffset: context.textOffset,
            selectionTransport: context.selectionTransport, prefix: prefix, module: item.module,
            startedAt: now(), proofKind: .keep, journaled: false))
    }

    private func suspend(_ item: Pending) {
        guard defaults.bool(forKey: PreferenceKey.automaticLearning), let language = item.entry.sourceLanguage else { return }
        store?.suspendLearnedRules(pattern: item.entry.original, language: language, module: item.module,
            app: item.entry.applicationBundleIdentifier, completion: rulesChanged)
    }

    private func safeContext() -> TextReplacementContext? { secureInput() ? nil : readContext() }

    private func sameRegion(_ item: Pending, _ context: TextReplacementContext) -> Bool {
        CFEqual(item.element, context.element) && item.textOffset == context.textOffset
            && item.selectionTransport == context.selectionTransport
    }

    private func learn(_ item: Pending, kind: RuleKind) {
        guard defaults.bool(forKey: PreferenceKey.automaticLearning), let source = item.entry.sourceLanguage,
              let target = item.entry.targetLanguage else { return }
        let proof = LearningProof(id: item.entry.eventID!, pattern: item.entry.original,
            replacement: item.entry.replacement, sourceLanguage: source, targetLanguage: target,
            module: item.module, kind: kind, applicationBundleIdentifier: item.entry.applicationBundleIdentifier, confirmedAt: now())
        proofObserver(proof)
        store?.recordProof(proof) { [weak self] learned in if learned { self?.rulesChanged() } }
    }

    private func evaluateRepairs(_ context: TextReplacementContext) {
        var consumed: [Int] = []
        for (index, repair) in repairs.enumerated() {
            let item = repair.pending
            guard item.entry.applicationBundleIdentifier == application(), sameRegion(item, context),
                  context.prefix.hasPrefix(repair.before), context.range.length == 0 else { continue }
            let tail = String(context.prefix.dropFirst(repair.before.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !tail.isEmpty, tail.count <= 32, let language = SpellLanguage.detect(in: tail).map({ $0 == .english ? InputLanguage.english : .russian }),
                  PersonalWordValidation.normalized(tail, language: language) != nil else { continue }
            if tail.lowercased() == item.entry.original.lowercased() {
                suspend(item)
                beginKeep(item, prefix: context.prefix, context: context)
            } else if language == item.entry.targetLanguage, let replacement = item.entry.replacement,
                      Self.distance(tail.lowercased(), replacement.lowercased()) <= 2 {
                var entry = item.entry
                entry = JournalEntry(id: 0, createdAt: now(), applicationBundleIdentifier: entry.applicationBundleIdentifier,
                    applicationName: entry.applicationName, original: entry.original, replacement: tail,
                    sourceLanguage: entry.sourceLanguage, targetLanguage: language, kind: .manualCorrection, eventID: UUID().uuidString)
                add(Pending(entry: entry, element: context.element, textOffset: context.textOffset,
                    selectionTransport: context.selectionTransport, prefix: context.prefix, module: item.module,
                    startedAt: now(), proofKind: .convert, journaled: false))
            } else { continue }
            consumed.append(index)
        }
        for index in consumed.reversed() { repairs.remove(at: index) }
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let left = Array(a), right = Array(b)
        var row = Array(0...right.count)
        for (i, character) in left.enumerated() {
            var next = [i + 1]
            for (j, other) in right.enumerated() { next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (character == other ? 0 : 1))) }
            row = next
        }
        return row.last ?? 0
    }
}
