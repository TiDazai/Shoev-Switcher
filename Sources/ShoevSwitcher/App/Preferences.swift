import Foundation

enum PreferenceKey {
    static let enabled = "enabled"
    static let automaticCorrection = "automaticCorrection"
    static let manualConversion = "manualConversion"
    static let manualShortcut = "manualShortcut"
    static let phraseContext = "phraseContext"
    static let applicationContext = "applicationContext"
    static let rememberApplicationLayout = "rememberApplicationLayout"
    static let correctionNotifications = "correctionNotifications"
    static let automaticLearning = "automaticLearning"
    static let undoAutomaticCorrection = "undoAutomaticCorrection"
    static let rememberUndoneCorrections = "rememberUndoneCorrections"
    static let journalEnabled = "journalEnabled"
    static let fullDiaryEnabled = "fullDiaryEnabled"
    static let hoverLanguageIndicator = "hoverLanguageIndicator"
    static let englishInputSource = "englishInputSource"
    static let russianInputSource = "russianInputSource"
    static let excludedApplications = "excludedApplications"
}

enum Preferences {
    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            PreferenceKey.enabled: true,
            PreferenceKey.automaticCorrection: true,
            PreferenceKey.manualConversion: true,
            PreferenceKey.manualShortcut: ManualShortcut.rightShift.rawValue,
            PreferenceKey.phraseContext: true,
            PreferenceKey.applicationContext: true,
            PreferenceKey.rememberApplicationLayout: false,
            PreferenceKey.correctionNotifications: true,
            PreferenceKey.automaticLearning: true,
            PreferenceKey.undoAutomaticCorrection: true,
            PreferenceKey.rememberUndoneCorrections: true,
            PreferenceKey.journalEnabled: true,
            PreferenceKey.fullDiaryEnabled: false,
            PreferenceKey.hoverLanguageIndicator: true,
            PreferenceKey.excludedApplications: [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.microsoft.VSCode",
                "com.apple.dt.Xcode"
            ]
        ])
    }
}
