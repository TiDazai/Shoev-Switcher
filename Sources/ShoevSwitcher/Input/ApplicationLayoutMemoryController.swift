import AppKit
import Foundation

final class ApplicationLayoutMemoryController {
    private let sourceManager: InputSourceManager
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var activeBundleIdentifier: String?

    init(sourceManager: InputSourceManager, defaults: UserDefaults = .standard) {
        self.sourceManager = sourceManager
        self.defaults = defaults
    }

    func start() {
        guard observer == nil else { return }
        activeBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.applicationDidActivate(notification)
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func applicationDidActivate(_ notification: Notification) {
        if defaults.bool(forKey: PreferenceKey.rememberApplicationLayout),
           let activeBundleIdentifier,
           let currentLanguage = sourceManager.currentLanguage() {
            var memory = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
            memory[activeBundleIdentifier] = currentLanguage.rawValue
            defaults.set(memory, forKey: storageKey)
        }

        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        activeBundleIdentifier = application?.bundleIdentifier
        guard defaults.bool(forKey: PreferenceKey.rememberApplicationLayout),
              let activeBundleIdentifier,
              let memory = defaults.dictionary(forKey: storageKey) as? [String: String],
              let rawLanguage = memory[activeBundleIdentifier],
              let language = InputLanguage(rawValue: rawLanguage) else { return }
        sourceManager.select(language)
    }

    private let storageKey = "applicationLayoutMemory"
}
