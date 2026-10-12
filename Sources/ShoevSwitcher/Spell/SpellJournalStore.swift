import AppKit

final class SpellJournalStore {
    private let store: JournalStore?
    private let defaults: UserDefaults
    private let didCorrect: () -> Void
    init(store: JournalStore? = nil, defaults: UserDefaults = .standard, didCorrect: @escaping () -> Void = {}) {
        self.store = store
        self.defaults = defaults
        self.didCorrect = didCorrect
    }
    func record(_ correction: Correction, application: NSRunningApplication?) {
        didCorrect()
        guard defaults.bool(forKey: SpellPreferenceKey.journalEnabled) else { return }
        let language: InputLanguage? = SpellLanguage.detect(in: correction.original).map {
            $0 == .english ? .english : .russian
        }
        store?.enqueue(JournalEntry(id: 0, createdAt: Date(),
            applicationBundleIdentifier: application?.bundleIdentifier, applicationName: application?.localizedName,
            original: correction.original, replacement: correction.replacement,
            sourceLanguage: language, targetLanguage: language, kind: .spelling))
    }
}
