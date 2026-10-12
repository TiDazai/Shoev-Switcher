import Foundation

enum SpellPreferenceKey {
    static let enabled = "spell.enabled"
    static let automaticCorrection = "spell.automaticCorrection"
    static let automaticPunctuation = "spell.automaticPunctuation"
    static let automaticCapitalization = "spell.automaticCapitalization"
    static let journalEnabled = "spell.journalEnabled"
    static let minimumLength = "spell.minimumLength"
    static let minimumScore = "spell.minimumScore"
    static let excludedApplications = "spell.excludedApplications"
}

enum SpellPreferences {
    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            SpellPreferenceKey.enabled: true,
            SpellPreferenceKey.automaticCorrection: true,
            SpellPreferenceKey.automaticPunctuation: true,
            SpellPreferenceKey.automaticCapitalization: true,
            SpellPreferenceKey.journalEnabled: true,
            SpellPreferenceKey.minimumLength: 3,
            SpellPreferenceKey.minimumScore: 250,
            SpellPreferenceKey.excludedApplications: [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.apple.dt.Xcode",
                "com.microsoft.VSCode"
            ]
        ])
    }
}
