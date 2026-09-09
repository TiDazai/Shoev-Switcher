import Foundation

enum PreferenceKey {
    static let enabled = "enabled"
    static let automaticCorrection = "automaticCorrection"
    static let journalEnabled = "journalEnabled"
    static let fullDiaryEnabled = "fullDiaryEnabled"
    static let englishInputSource = "englishInputSource"
    static let russianInputSource = "russianInputSource"
    static let excludedApplications = "excludedApplications"
}

enum Preferences {
    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            PreferenceKey.enabled: true,
            PreferenceKey.automaticCorrection: true,
            PreferenceKey.journalEnabled: true,
            PreferenceKey.fullDiaryEnabled: false,
            PreferenceKey.excludedApplications: [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.microsoft.VSCode",
                "com.apple.dt.Xcode"
            ]
        ])
    }
}
