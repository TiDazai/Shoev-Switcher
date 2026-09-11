import Foundation

final class ApplicationLanguageProfileStore {
    private let defaults: UserDefaults
    private var profiles: [String: [String: Int]]
    private var pendingSave: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = defaults.dictionary(forKey: storageKey) as? [String: [String: Int]] ?? [:]
    }

    func observe(_ language: InputLanguage, applicationBundleIdentifier: String?) {
        guard let applicationBundleIdentifier, !applicationBundleIdentifier.isEmpty else { return }
        var counts = profiles[applicationBundleIdentifier] ?? [:]
        counts[language.rawValue, default: 0] += 1
        let total = counts.values.reduce(0, +)
        if total > 200 {
            for key in counts.keys { counts[key] = max(1, (counts[key] ?? 0) / 2) }
        }
        profiles[applicationBundleIdentifier] = counts
        scheduleSave()
    }

    func preferredLanguage(for applicationBundleIdentifier: String?) -> InputLanguage? {
        guard let applicationBundleIdentifier,
              let counts = profiles[applicationBundleIdentifier] else { return nil }
        let english = counts[InputLanguage.english.rawValue, default: 0]
        let russian = counts[InputLanguage.russian.rawValue, default: 0]
        guard max(english, russian) >= 3, english != russian else { return nil }
        return english > russian ? .english : .russian
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        defaults.set(profiles, forKey: storageKey)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private let storageKey = "applicationLanguageProfiles"
}
