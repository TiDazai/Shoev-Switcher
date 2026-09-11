import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sourceManager = InputSourceManager()
    private let ruleStore = RuleStore()
    private let keyboardMonitor = KeyboardMonitor()

    private var journalStore: JournalStore?
    private var inputEngine: InputEngine?
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var journalWindowController: JournalWindowController?
    private var hoverIndicator: TextInputHoverIndicator?
    private var layoutMemoryController: ApplicationLayoutMemoryController?
    private var applicationProfiles: ApplicationLanguageProfileStore?
    private var correctionNotifier: CorrectionNotifier?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        journalStore = try? JournalStore()
        if let journalStore {
            ruleStore.replaceRules(journalStore.loadRules())
        }

        let detector = LanguageDetector(rules: ruleStore)
        let profiles = ApplicationLanguageProfileStore()
        let notifier = CorrectionNotifier()
        applicationProfiles = profiles
        correctionNotifier = notifier
        let engine = InputEngine(
            sourceManager: sourceManager,
            detector: detector,
            ruleStore: ruleStore,
            journalStore: journalStore,
            correctionNotifier: notifier,
            applicationProfiles: profiles
        )
        inputEngine = engine
        keyboardMonitor.delegate = engine

        let hoverIndicator = TextInputHoverIndicator(sourceManager: sourceManager)
        self.hoverIndicator = hoverIndicator
        keyboardMonitor.mouseMovedHandler = { [weak hoverIndicator] point in
            hoverIndicator?.mouseMoved(to: point)
        }
        keyboardMonitor.inputActivityHandler = { [weak hoverIndicator] in
            hoverIndicator?.inputActivityOccurred()
        }

        let layoutMemory = ApplicationLayoutMemoryController(sourceManager: sourceManager)
        layoutMemoryController = layoutMemory
        layoutMemory.start()

        menuBarController = MenuBarController(
            monitor: keyboardMonitor,
            sourceManager: sourceManager,
            openSettings: { [weak self] in self?.showSettings() },
            openJournal: { [weak self] in self?.showJournal() },
            hoverIndicatorChanged: { [weak self] in self?.hoverIndicator?.preferenceDidChange() }
        )

        if !keyboardMonitor.start() {
            keyboardMonitor.requestRequiredPermissions()
            startPermissionWatcher()
        }
        menuBarController?.refresh()

    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        hoverIndicator?.stop()
        correctionNotifier?.hide()
        applicationProfiles?.flush()
        layoutMemoryController?.stop()
        keyboardMonitor.stop()
    }

    private func startPermissionWatcher() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard self.keyboardMonitor.start() else { return }
            self.menuBarController?.refresh()
            timer.invalidate()
            self.permissionTimer = nil
        }
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                monitor: keyboardMonitor,
                sourceManager: sourceManager,
                onSaved: { [weak self] in
                    self?.sourceManager.reloadSources()
                    self?.menuBarController?.refresh()
                    self?.hoverIndicator?.preferenceDidChange()
                    if self?.keyboardMonitor.start() != true {
                        self?.keyboardMonitor.requestRequiredPermissions()
                        self?.startPermissionWatcher()
                    }
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    private func showJournal() {
        guard let journalStore else { return }
        if journalWindowController == nil {
            journalWindowController = JournalWindowController(
                store: journalStore,
                onRulesChanged: { [weak self] in self?.inputEngine?.reloadRules() }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        journalWindowController?.showWindow(nil)
        journalWindowController?.reload()
    }
}
