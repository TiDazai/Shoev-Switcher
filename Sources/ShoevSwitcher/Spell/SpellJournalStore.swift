import AppKit

final class SpellJournalStore {
    private let store: JournalStore?
    private let defaults: UserDefaults
    private let didCorrect: (Correction) -> Void
    private let learning: AdaptiveLearningController?
    init(store: JournalStore? = nil, defaults: UserDefaults = .standard,
         learning: AdaptiveLearningController? = nil, didCorrect: @escaping (Correction) -> Void = { _ in }) {
        self.store = store
        self.defaults = defaults
        self.didCorrect = didCorrect
        self.learning = learning
    }
    func record(_ correction: Correction, application: NSRunningApplication?, expectedPrefix: String? = nil) {
        didCorrect(correction)
        let language: InputLanguage? = SpellLanguage.detect(in: correction.original).map {
            $0 == .english ? .english : .russian
        }
        let entry = JournalEntry(id: 0, createdAt: Date(),
            applicationBundleIdentifier: application?.bundleIdentifier, applicationName: application?.localizedName,
            original: correction.original, replacement: correction.replacement,
            sourceLanguage: language, targetLanguage: language, kind: .spelling)
        let enabled = defaults.bool(forKey: SpellPreferenceKey.journalEnabled)
        if let learning { learning.record(entry, module: .spell, journalEnabled: enabled, expectedPrefix: expectedPrefix) }
        else if enabled { store?.enqueue(entry) }
    }
}
