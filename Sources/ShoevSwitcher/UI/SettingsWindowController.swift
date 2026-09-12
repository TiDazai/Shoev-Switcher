import AppKit

final class SettingsWindowController: NSWindowController {
    private let monitor: KeyboardMonitor
    private let sourceManager: InputSourceManager
    private let onSaved: () -> Void

    private let enabledCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let automaticCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let manualCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let phraseContextCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let applicationContextCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let layoutMemoryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let learningCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let undoCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let rememberUndoCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let hoverIndicatorCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let correctionNotificationsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let journalCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let fullDiaryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private let englishPopup = NSPopUpButton()
    private let russianPopup = NSPopUpButton()
    private let exclusionsView = NSTextView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let manualShortcutPopup = NSPopUpButton()

    init(monitor: KeyboardMonitor, sourceManager: InputSourceManager, onSaved: @escaping () -> Void) {
        self.monitor = monitor
        self.sourceManager = sourceManager
        self.onSaved = onSaved
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 590),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки Shoev Switcher"
        window.center()
        super.init(window: window)
        buildInterface()
        reloadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        reloadValues()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        configureCheckbox(enabledCheckbox, title: "Shoev Switcher включён")
        configureCheckbox(automaticCheckbox, title: "Исправлять раскладку автоматически")
        configureCheckbox(manualCheckbox, title: "Ручная конвертация двойным выбранным Shift")
        configureCheckbox(phraseContextCheckbox, title: "Учитывать предыдущие слова и частые фразы")
        configureCheckbox(applicationContextCheckbox, title: "Учитывать привычный язык каждого приложения")
        configureCheckbox(layoutMemoryCheckbox, title: "Запоминать и восстанавливать раскладку приложений")
        configureCheckbox(learningCheckbox, title: "Обучаться после повторных ручных исправлений")
        configureCheckbox(undoCheckbox, title: "Отменять автоисправление клавишей Backspace")
        configureCheckbox(rememberUndoCheckbox, title: "Запоминать отменённое исправление как исключение")
        configureCheckbox(hoverIndicatorCheckbox, title: "Показывать флаг раскладки рядом с курсором")
        configureCheckbox(correctionNotificationsCheckbox, title: "Показывать короткое уведомление об исправлении")
        configureCheckbox(journalCheckbox, title: "Сохранять журнал исправлений")
        configureCheckbox(fullDiaryCheckbox, title: "Сохранять все завершённые слова")
        for shortcut in ManualShortcut.allCases {
            manualShortcutPopup.addItem(withTitle: shortcut.title)
            manualShortcutPopup.lastItem?.representedObject = shortcut.rawValue
        }

        let tabs = NSTabView()
        tabs.addTabViewItem(makeBehaviorTab())
        tabs.addTabViewItem(makeInterfaceAndLearningTab())
        tabs.addTabViewItem(makeLayoutsTab())
        tabs.addTabViewItem(makePrivacyTab())

        let saveButton = NSButton(title: "Сохранить", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let root = NSStackView(views: [tabs, saveButton])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        tabs.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            tabs.widthAnchor.constraint(equalTo: root.widthAnchor),
            tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 500)
        ])
    }

    private func makeBehaviorTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "behavior")
        item.label = "Поведение"
        item.view = tabContent([
            option(enabledCheckbox, "Главный выключатель приложения."),
            option(automaticCheckbox, "Проверять слова на границе и исправлять неверную раскладку."),
            option(manualCheckbox, "Конвертировать выделение, текущее или последнее слово выбранным двойным Shift."),
            labeledControl("Горячая клавиша:", manualShortcutPopup),
            option(phraseContextCheckbox, "Использовать до пяти предыдущих слов для коротких и неоднозначных фраз."),
            option(applicationContextCheckbox, "Мягко учитывать, какой язык чаще используется в текущем приложении."),
            option(layoutMemoryCheckbox, "При возврате в приложение включать последнюю использованную там раскладку.")
        ])
        return item
    }

    private func makeInterfaceAndLearningTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "interfaceAndLearning")
        item.label = "Интерфейс и обучение"
        item.view = tabContent([
            option(learningCheckbox, "После двух одинаковых ручных исправлений создать личное правило."),
            option(undoCheckbox, "Вернуть ошибочно исправленное слово сразу после замены."),
            option(rememberUndoCheckbox, "Автоматически добавить правило «никогда не менять» после отмены."),
            option(hoverIndicatorCheckbox, "Показывать 🇷🇺 или 🇬🇧 рядом с указателем над доступным полем ввода."),
            option(correctionNotificationsCheckbox, "На секунду показывать «было → стало» рядом с кареткой.")
        ])
        return item
    }

    private func makeLayoutsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "layouts")
        item.label = "Раскладки"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "English:"), englishPopup],
            [NSTextField(labelWithString: "Русский:"), russianPopup]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 10
        grid.columnSpacing = 12

        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.maximumNumberOfLines = 3
        let permissionButton = NSButton(
            title: "Проверить и запросить разрешения",
            target: self,
            action: #selector(requestPermissions)
        )
        let note = NSTextField(wrappingLabelWithString: "Shoev Switcher работает только с выбранными источниками English и Русский. Парольные поля и Secure Event Input всегда игнорируются и не могут быть включены в настройках.")
        note.textColor = .secondaryLabelColor

        let content = tabContent([
            sectionTitle("Источники ввода"),
            grid,
            sectionTitle("Системные разрешения"),
            permissionLabel,
            permissionButton,
            note
        ])
        grid.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -36).isActive = true
        item.view = content
        return item
    }

    private func makePrivacyTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "privacy")
        item.label = "Дневник и исключения"

        let exclusionsLabel = NSTextField(labelWithString: "Не обрабатывать в этих приложениях (Bundle ID, по одному в строке):")
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = exclusionsView
        exclusionsView.isRichText = false
        exclusionsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let note = NSTextField(wrappingLabelWithString: "Дневник и правила хранятся только на этом Mac. Текстовые поля локальной базы зашифрованы.")
        note.textColor = .secondaryLabelColor

        let content = tabContent([
            option(journalCheckbox, "Хранить автоматические, ручные и отменённые исправления."),
            option(fullDiaryCheckbox, "Дополнительно хранить слова, которые приложение оставило без изменений."),
            sectionTitle("Исключённые приложения"),
            exclusionsLabel,
            scrollView,
            note
        ])
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -36).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 190).isActive = true
        item.view = content
        return item
    }

    private func tabContent(_ views: [NSView]) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18)
        ])
        return container
    }

    private func option(_ checkbox: NSButton, _ detail: String) -> NSView {
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [checkbox, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20).isActive = true
        return stack
    }

    private func labeledControl(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        return row
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }

    private func configureCheckbox(_ checkbox: NSButton, title: String) {
        checkbox.title = title
        checkbox.target = self
        checkbox.action = #selector(optionChanged)
    }

    private func reloadValues() {
        sourceManager.reloadSources()
        populate(englishPopup, sources: sourceManager.allSources(for: .english), selected: sourceManager.englishSource)
        populate(russianPopup, sources: sourceManager.allSources(for: .russian), selected: sourceManager.russianSource)

        let defaults = UserDefaults.standard
        set(enabledCheckbox, from: PreferenceKey.enabled, defaults: defaults)
        set(automaticCheckbox, from: PreferenceKey.automaticCorrection, defaults: defaults)
        set(manualCheckbox, from: PreferenceKey.manualConversion, defaults: defaults)
        set(phraseContextCheckbox, from: PreferenceKey.phraseContext, defaults: defaults)
        set(applicationContextCheckbox, from: PreferenceKey.applicationContext, defaults: defaults)
        set(layoutMemoryCheckbox, from: PreferenceKey.rememberApplicationLayout, defaults: defaults)
        set(learningCheckbox, from: PreferenceKey.automaticLearning, defaults: defaults)
        set(undoCheckbox, from: PreferenceKey.undoAutomaticCorrection, defaults: defaults)
        set(rememberUndoCheckbox, from: PreferenceKey.rememberUndoneCorrections, defaults: defaults)
        set(hoverIndicatorCheckbox, from: PreferenceKey.hoverLanguageIndicator, defaults: defaults)
        set(correctionNotificationsCheckbox, from: PreferenceKey.correctionNotifications, defaults: defaults)
        set(journalCheckbox, from: PreferenceKey.journalEnabled, defaults: defaults)
        set(fullDiaryCheckbox, from: PreferenceKey.fullDiaryEnabled, defaults: defaults)
        let shortcut = defaults.string(forKey: PreferenceKey.manualShortcut) ?? ManualShortcut.rightShift.rawValue
        manualShortcutPopup.selectItem(
            at: manualShortcutPopup.itemArray.firstIndex {
                ($0.representedObject as? String) == shortcut
            } ?? 0
        )

        let exclusions = defaults.stringArray(forKey: PreferenceKey.excludedApplications) ?? []
        exclusionsView.string = exclusions.sorted().joined(separator: "\n")
        permissionLabel.stringValue = monitor.hasRequiredPermissions
            ? "Системные разрешения выданы. Мониторинг и исправление ввода доступны."
            : "Нужны Input Monitoring и Accessibility. После выдачи разрешений приложение может потребоваться перезапустить."
        updateDependencies()
    }

    private func populate(_ popup: NSPopUpButton, sources: [InputSourceManager.Source], selected: InputSourceManager.Source?) {
        popup.removeAllItems()
        for source in sources {
            popup.addItem(withTitle: source.name.isEmpty ? source.identifier : source.name)
            popup.lastItem?.representedObject = source.identifier
        }
        if let selected,
           let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected.identifier }) {
            popup.selectItem(at: index)
        }
    }

    private func set(_ checkbox: NSButton, from key: String, defaults: UserDefaults) {
        checkbox.state = defaults.bool(forKey: key) ? .on : .off
    }

    @objc private func optionChanged() {
        updateDependencies()
    }

    private func updateDependencies() {
        phraseContextCheckbox.isEnabled = automaticCheckbox.state == .on
        applicationContextCheckbox.isEnabled = automaticCheckbox.state == .on
        undoCheckbox.isEnabled = automaticCheckbox.state == .on
        rememberUndoCheckbox.isEnabled = undoCheckbox.isEnabled && undoCheckbox.state == .on
        learningCheckbox.isEnabled = manualCheckbox.state == .on
        fullDiaryCheckbox.isEnabled = journalCheckbox.state == .on
    }

    @objc private func requestPermissions() {
        monitor.requestRequiredPermissions()
        monitor.start()
        reloadValues()
    }

    @objc private func saveSettings() {
        let defaults = UserDefaults.standard
        savePreference(enabledCheckbox, to: PreferenceKey.enabled, defaults: defaults)
        savePreference(automaticCheckbox, to: PreferenceKey.automaticCorrection, defaults: defaults)
        savePreference(manualCheckbox, to: PreferenceKey.manualConversion, defaults: defaults)
        savePreference(phraseContextCheckbox, to: PreferenceKey.phraseContext, defaults: defaults)
        savePreference(applicationContextCheckbox, to: PreferenceKey.applicationContext, defaults: defaults)
        savePreference(layoutMemoryCheckbox, to: PreferenceKey.rememberApplicationLayout, defaults: defaults)
        savePreference(learningCheckbox, to: PreferenceKey.automaticLearning, defaults: defaults)
        savePreference(undoCheckbox, to: PreferenceKey.undoAutomaticCorrection, defaults: defaults)
        savePreference(rememberUndoCheckbox, to: PreferenceKey.rememberUndoneCorrections, defaults: defaults)
        savePreference(hoverIndicatorCheckbox, to: PreferenceKey.hoverLanguageIndicator, defaults: defaults)
        savePreference(correctionNotificationsCheckbox, to: PreferenceKey.correctionNotifications, defaults: defaults)
        savePreference(journalCheckbox, to: PreferenceKey.journalEnabled, defaults: defaults)
        savePreference(fullDiaryCheckbox, to: PreferenceKey.fullDiaryEnabled, defaults: defaults)
        if let shortcut = manualShortcutPopup.selectedItem?.representedObject as? String {
            defaults.set(shortcut, forKey: PreferenceKey.manualShortcut)
        }

        if let identifier = englishPopup.selectedItem?.representedObject as? String {
            defaults.set(identifier, forKey: PreferenceKey.englishInputSource)
        }
        if let identifier = russianPopup.selectedItem?.representedObject as? String {
            defaults.set(identifier, forKey: PreferenceKey.russianInputSource)
        }
        let exclusions = exclusionsView.string
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        defaults.set(exclusions, forKey: PreferenceKey.excludedApplications)
        onSaved()
        window?.close()
    }

    private func savePreference(_ checkbox: NSButton, to key: String, defaults: UserDefaults) {
        defaults.set(checkbox.state == .on, forKey: key)
    }
}
