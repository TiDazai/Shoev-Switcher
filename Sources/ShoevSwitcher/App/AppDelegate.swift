import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sourceManager = InputSourceManager()
    private let ruleStore = RuleStore()
    private let keyboardMonitor = KeyboardMonitor()
    private let injector = EventInjector()
    private var journalStore: JournalStore?
    private var inputEngine: InputEngine?
    private var spellEngine: SpellInputEngine?
    private var coordinator: UnifiedInputCoordinator?
    private var menuBarController: MenuBarController?
    private var journalWindowController: JournalWindowController?
    private var journalContent: NSView?
    private var applicationWindowController: ApplicationWindowController?
    private var applicationModel: ApplicationModel?
    private var hoverIndicator: TextInputHoverIndicator?
    private var layoutMemoryController: ApplicationLayoutMemoryController?
    private var applicationProfiles: ApplicationLanguageProfileStore?
    private var correctionNotifier: CorrectionNotifier?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        Preferences.registerDefaults()
        SpellPreferences.register()
        journalStore = try? JournalStore()
        if let journalStore { ruleStore.replaceRules(journalStore.loadRules()) }
        let profiles = ApplicationLanguageProfileStore()
        let notifier = CorrectionNotifier()
        applicationProfiles = profiles
        correctionNotifier = notifier
        let engine = InputEngine(sourceManager: sourceManager,
            detector: LanguageDetector(rules: ruleStore), ruleStore: ruleStore, journalStore: journalStore,
            injector: injector, correctionNotifier: notifier, applicationProfiles: profiles)
        inputEngine = engine

        let model = ApplicationModel(monitor: keyboardMonitor, sourceManager: sourceManager)
        applicationModel = model
        let spell = SpellInputEngine(injector: SpellTextInjector(injector: injector),
            journal: SpellJournalStore(store: journalStore, didCorrect: { [weak self] in
                guard let self else { return }
                self.inputEngine?.keyboardMonitorDidResetInput(self.keyboardMonitor)
            }))
        spellEngine = spell
        let pipeline = UnifiedInputCoordinator(switcher: engine, spell: spell,
            conversionPending: { [weak engine] in engine?.didScheduleAutomaticCorrection == true },
            standaloneRunning: { [weak model] in model?.standaloneSpellRunning == true })
        coordinator = pipeline
        keyboardMonitor.delegate = pipeline

        let indicator = TextInputHoverIndicator(sourceManager: sourceManager)
        hoverIndicator = indicator
        keyboardMonitor.mouseMovedHandler = { [weak indicator] point in indicator?.mouseMoved(to: point) }
        keyboardMonitor.inputActivityHandler = { [weak indicator] in indicator?.inputActivityOccurred() }
        let layoutMemory = ApplicationLayoutMemoryController(sourceManager: sourceManager)
        layoutMemoryController = layoutMemory
        layoutMemory.start()

        model.preferencesChanged = { [weak self] in self?.applyPreferences() }
        model.journalView = { [weak self] in self?.makeJournalContent() ?? NSView() }
        model.reloadJournal = { [weak self] in self?.journalWindowController?.reload() }
        applicationWindowController = ApplicationWindowController(model: model)

        menuBarController = MenuBarController(monitor: keyboardMonitor, sourceManager: sourceManager,
            openSettings: { [weak self] in self?.applicationWindowController?.open(.switcher) },
            openJournal: { [weak self] in self?.applicationWindowController?.open(.journal) },
            hoverIndicatorChanged: { [weak self] in self?.hoverIndicator?.preferenceDidChange() },
            openApplication: { [weak self] in self?.applicationWindowController?.open() })
        configureMainMenu()
        if !keyboardMonitor.start() { keyboardMonitor.requestRequiredPermissions() }
        startPermissionWatcher()
        menuBarController?.refresh()
        applicationWindowController?.open()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        applicationWindowController?.open()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        applicationModel?.stopRefresh()
        injector.cancelPending()
        hoverIndicator?.stop()
        correctionNotifier?.hide()
        applicationProfiles?.flush()
        journalStore?.flush()
        layoutMemoryController?.stop()
        keyboardMonitor.stop()
    }
    private func applyPreferences() {
        injector.cancelPending()
        coordinator?.keyboardMonitorDidResetInput(keyboardMonitor)
        sourceManager.reloadSources()
        menuBarController?.refresh()
        hoverIndicator?.preferenceDidChange()
    }
    private func startPermissionWatcher() {
        permissionTimer?.invalidate()
        permissionTimer = .scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if !self.keyboardMonitor.hasRequiredPermissions { _ = self.keyboardMonitor.start() }
            self.menuBarController?.refresh()
        }
    }
    private func makeJournalContent() -> NSView {
        if let journalContent { return journalContent }
        guard let journalStore else {
            return NSTextField(wrappingLabelWithString: "Не удалось открыть локальный дневник. Проверь доступ к Application Support.")
        }
        let controller = JournalWindowController(store: journalStore,
            onRulesChanged: { [weak self] in self?.inputEngine?.reloadRules() })
        journalWindowController = controller
        let content = controller.detachContentView()
        journalContent = content
        controller.reload()
        return content
    }
    private func configureMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        applicationItem.title = "Shoev Switcher"
        let application = NSMenu()
        application.addItem(withTitle: "О Shoev Switcher", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        let settings = application.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        application.addItem(withTitle: "Скрыть Shoev Switcher", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(.separator())
        application.addItem(withTitle: "Завершить Shoev Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = application
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        editItem.title = "Правка"
        let edit = NSMenu(title: "Правка")
        for (title, selector, key) in [
            ("Отменить", Selector(("undo:")), "z"), ("Вырезать", #selector(NSText.cut(_:)), "x"),
            ("Копировать", #selector(NSText.copy(_:)), "c"), ("Вставить", #selector(NSText.paste(_:)), "v"),
            ("Выбрать всё", #selector(NSText.selectAll(_:)), "a")
        ] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc private func showSettings() { applicationWindowController?.open(.switcher) }
}
