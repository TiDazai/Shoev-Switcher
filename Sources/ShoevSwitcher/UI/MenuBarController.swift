import AppKit
import ServiceManagement

final class MenuBarController: NSObject, NSMenuDelegate {
    private let monitor: KeyboardMonitor
    private let sourceManager: InputSourceManager
    private let openSettings: () -> Void
    private let openJournal: () -> Void
    private let hoverIndicatorChanged: () -> Void
    private let openApplication: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private lazy var enabledItem = makeItem("Модуль Switcher включён", #selector(toggleEnabled))
    private lazy var automaticItem = makeItem("Исправлять автоматически", #selector(toggleAutomatic))
    private lazy var spellItem = makeItem("Модуль Spell включён", #selector(toggleSpell))
    private lazy var hoverIndicatorItem = makeItem("Показывать флаг у курсора", #selector(toggleHoverIndicator))
    private lazy var journalItem = makeItem("Журнал исправлений", #selector(toggleJournal))
    private lazy var fullDiaryItem = makeItem("Записывать обычный набор в журнал", #selector(toggleFullDiary))
    private lazy var launchAtLoginItem = makeItem("Запускать при входе", #selector(toggleLaunchAtLogin))
    private lazy var permissionItem = makeItem("Выдать системные разрешения…", #selector(requestPermissions))

    init(
        monitor: KeyboardMonitor,
        sourceManager: InputSourceManager,
        openSettings: @escaping () -> Void,
        openJournal: @escaping () -> Void,
        hoverIndicatorChanged: @escaping () -> Void,
        openApplication: @escaping () -> Void = {}
    ) {
        self.monitor = monitor
        self.sourceManager = sourceManager
        self.openSettings = openSettings
        self.openJournal = openJournal
        self.hoverIndicatorChanged = hoverIndicatorChanged
        self.openApplication = openApplication
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        configureMenu()
    }

    func refresh() {
        let defaults = UserDefaults.standard
        enabledItem.state = defaults.bool(forKey: PreferenceKey.enabled) ? .on : .off
        automaticItem.state = defaults.bool(forKey: PreferenceKey.automaticCorrection) ? .on : .off
        spellItem.state = defaults.bool(forKey: SpellPreferenceKey.enabled) ? .on : .off
        hoverIndicatorItem.state = defaults.bool(forKey: PreferenceKey.hoverLanguageIndicator) ? .on : .off
        journalItem.state = defaults.bool(forKey: PreferenceKey.journalEnabled) ? .on : .off
        fullDiaryItem.state = defaults.bool(forKey: PreferenceKey.fullDiaryEnabled) ? .on : .off
        fullDiaryItem.isEnabled = journalItem.state == .on
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissionItem.isHidden = monitor.hasRequiredPermissions

        let enabled = defaults.bool(forKey: PreferenceKey.enabled) || defaults.bool(forKey: SpellPreferenceKey.enabled)
        statusItem.button?.alphaValue = enabled ? 1 : 0.45
        statusItem.button?.toolTip = monitor.hasRequiredPermissions
            ? Brand.productName
            : "\(Brand.productName): — нужны системные разрешения"
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
                .flatMap(NSImage.init(contentsOf:))
            image?.isTemplate = false
            button.contentTintColor = nil
            image?.size = NSSize(width: 18, height: 18)
            image?.accessibilityDescription = Brand.productName
            button.image = image ?? NSImage(
                systemSymbolName: "arrow.left.arrow.right",
                accessibilityDescription: Brand.productName
            )
            button.imagePosition = .imageOnly
        }
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self
        menu.addItem(makeItem("Открыть \(Brand.productName)…", #selector(showApplication)))
        menu.addItem(.separator())
        menu.addItem(enabledItem)
        menu.addItem(spellItem)
        menu.addItem(automaticItem)
        menu.addItem(hoverIndicatorItem)
        menu.addItem(.separator())
        menu.addItem(journalItem)
        menu.addItem(fullDiaryItem)
        menu.addItem(makeItem("Открыть журнал…", #selector(showJournal)))
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(permissionItem)
        menu.addItem(makeItem("Настройки…", #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem("Завершить \(Brand.productName)", #selector(quit), keyEquivalent: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent).configured(target: self)
    }

    @objc private func toggleEnabled() {
        togglePreference(PreferenceKey.enabled)
    }
    @objc private func toggleSpell() { togglePreference(SpellPreferenceKey.enabled) }
    @objc private func showApplication() { openApplication() }

    @objc private func toggleAutomatic() {
        togglePreference(PreferenceKey.automaticCorrection)
    }

    @objc private func toggleHoverIndicator() {
        togglePreference(PreferenceKey.hoverLanguageIndicator)
        hoverIndicatorChanged()
    }

    @objc private func toggleJournal() {
        togglePreference(PreferenceKey.journalEnabled)
    }

    @objc private func toggleFullDiary() {
        togglePreference(PreferenceKey.fullDiaryEnabled)
    }

    @objc private func showJournal() {
        openJournal()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func requestPermissions() {
        monitor.requestRequiredPermissions()
        monitor.start()
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Не удалось изменить запуск при входе"
            alert.runModal()
        }
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func togglePreference(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        refresh()
    }
}

private extension NSMenuItem {
    func configured(target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
