import AppKit
import UniformTypeIdentifiers

final class JournalWindowController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSSearchFieldDelegate {

    private enum ViewMode { case journal, rules }

    private let store: JournalStore
    private let onRulesChanged: () -> Void
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let filterPopup = NSPopUpButton()
    private let modeControl = NSSegmentedControl(labels: ["Дневник", "Правила"], trackingMode: .selectOne, target: nil, action: nil)
    private let journalButtons = NSStackView()
    private let ruleButtons = NSStackView()

    private var mode: ViewMode = .journal
    private var allEntries: [JournalEntry] = []
    private var visibleEntries: [JournalViewEntry] = []
    private var allRules: [UserRule] = []
    private var visibleRules: [UserRule] = []

    init(store: JournalStore, onRulesChanged: @escaping () -> Void) {
        self.store = store
        self.onRulesChanged = onRulesChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Дневник и правила Shoev Switcher"
        window.center()
        super.init(window: window)
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        store.recentEntries(limit: 5_000) { [weak self] entries in
            self?.allEntries = entries
            self?.applyFilters()
        }
        store.rules { [weak self] rules in
            self?.allRules = rules
            self?.applyFilters()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        mode == .journal ? visibleEntries.count : visibleRules.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier.rawValue else { return nil }
        let value: String
        switch mode {
        case .journal:
            guard row < visibleEntries.count else { return nil }
            let entry = visibleEntries[row]
            switch identifier {
            case "time": value = entry.time
            case "app": value = entry.application
            case "original": value = entry.value.original
            case "replacement": value = entry.value.replacement ?? "—"
            default: value = entry.kind
            }
        case .rules:
            guard row < visibleRules.count else { return nil }
            let rule = visibleRules[row]
            switch identifier {
            case "kind": value = rule.kind.title
            case "pattern": value = rule.pattern
            case "replacement": value = rule.replacement ?? "—"
            case "language": value = rule.language?.title ?? "Любой"
            default: value = rule.applicationBundleIdentifier ?? "Все приложения"
            }
        }
        let field = NSTextField(labelWithString: value)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = value
        return field
    }

    func controlTextDidChange(_ notification: Notification) {
        applyFilters()
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(switchViewMode)

        searchField.placeholderString = "Поиск"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true

        filterPopup.addItems(withTitles: ["Все события", "Автоматические", "Ручные", "Отменённые", "Набранные"])
        for (index, value) in ["all", "correction", "manualCorrection", "undone", "typed"].enumerated() {
            filterPopup.item(at: index)?.representedObject = value
        }
        filterPopup.target = self
        filterPopup.action = #selector(filterChanged)

        let toolbar = NSStackView(views: [modeControl, searchField, filterPopup])
        toolbar.orientation = .horizontal
        toolbar.spacing = 10
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.doubleAction = #selector(editSelectedRule)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        configureJournalButtons()
        configureRuleButtons()
        ruleButtons.isHidden = true

        let root = NSStackView(views: [toolbar, scrollView, journalButtons, ruleButtons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.detachesHiddenViews = true
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        journalButtons.translatesAutoresizingMaskIntoConstraints = false
        ruleButtons.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            toolbar.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            journalButtons.widthAnchor.constraint(equalTo: root.widthAnchor),
            ruleButtons.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        configureColumns()
    }

    private func configureJournalButtons() {
        let buttons = [
            NSButton(title: "Никогда не менять", target: self, action: #selector(addKeepRule)),
            NSButton(title: "Всегда менять", target: self, action: #selector(addConvertRule)),
            NSButton(title: "+ Русский", target: self, action: #selector(addRussianWord)),
            NSButton(title: "+ English", target: self, action: #selector(addEnglishWord)),
            NSButton(title: "Удалить запись", target: self, action: #selector(deleteSelectedEntry)),
            NSView(),
            NSButton(title: "Очистить дневник", target: self, action: #selector(clearJournal))
        ]
        journalButtons.setViews(buttons, in: .leading)
        journalButtons.orientation = .horizontal
        journalButtons.spacing = 8
    }

    private func configureRuleButtons() {
        let buttons = [
            NSButton(title: "Добавить…", target: self, action: #selector(addRule)),
            NSButton(title: "Изменить…", target: self, action: #selector(editSelectedRule)),
            NSButton(title: "Удалить", target: self, action: #selector(deleteSelectedRule)),
            NSView(),
            NSButton(title: "Импорт…", target: self, action: #selector(importRules)),
            NSButton(title: "Экспорт…", target: self, action: #selector(exportRules))
        ]
        ruleButtons.setViews(buttons, in: .leading)
        ruleButtons.orientation = .horizontal
        ruleButtons.spacing = 8
    }

    private func configureColumns() {
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        switch mode {
        case .journal:
            addColumn("time", title: "Время", width: 125)
            addColumn("app", title: "Приложение", width: 140)
            addColumn("original", title: "Было", width: 210)
            addColumn("replacement", title: "Стало", width: 210)
            addColumn("kind", title: "Действие", width: 120)
        case .rules:
            addColumn("kind", title: "Правило", width: 135)
            addColumn("pattern", title: "Слово", width: 210)
            addColumn("replacement", title: "Замена", width: 210)
            addColumn("language", title: "Язык", width: 100)
            addColumn("app", title: "Приложение", width: 180)
        }
        tableView.reloadData()
    }

    private func addColumn(_ identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private func applyFilters() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch mode {
        case .journal:
            let kind = filterPopup.selectedItem?.representedObject as? String ?? "all"
            visibleEntries = allEntries.filter { entry in
                let matchesKind = kind == "all" || entry.kind.rawValue == kind
                let haystack = [
                    entry.original,
                    entry.replacement ?? "",
                    entry.applicationName ?? "",
                    entry.applicationBundleIdentifier ?? ""
                ].joined(separator: " ").lowercased()
                return matchesKind && (query.isEmpty || haystack.contains(query))
            }.map(JournalViewEntry.init)
        case .rules:
            visibleRules = allRules.filter { rule in
                let haystack = [
                    rule.kind.title,
                    rule.pattern,
                    rule.replacement ?? "",
                    rule.language?.title ?? "",
                    rule.applicationBundleIdentifier ?? ""
                ].joined(separator: " ").lowercased()
                return query.isEmpty || haystack.contains(query)
            }
        }
        tableView.reloadData()
    }

    private var selectedEntry: JournalEntry? {
        let row = tableView.selectedRow
        guard mode == .journal, row >= 0, row < visibleEntries.count else { return nil }
        return visibleEntries[row].value
    }

    private var selectedRule: UserRule? {
        let row = tableView.selectedRow
        guard mode == .rules, row >= 0, row < visibleRules.count else { return nil }
        return visibleRules[row]
    }

    @objc private func switchViewMode() {
        mode = modeControl.selectedSegment == 0 ? .journal : .rules
        filterPopup.isHidden = mode == .rules
        journalButtons.isHidden = mode == .rules
        ruleButtons.isHidden = mode == .journal
        configureColumns()
        applyFilters()
    }

    @objc private func filterChanged() { applyFilters() }

    @objc private func addKeepRule() {
        guard let entry = selectedEntry else { return }
        store.addRule(kind: .keep, pattern: entry.original, language: entry.sourceLanguage) { [weak self] in
            self?.rulesDidChange()
        }
    }

    @objc private func addConvertRule() {
        guard let entry = selectedEntry, let replacement = entry.replacement else { return }
        store.addRule(
            kind: .convert,
            pattern: entry.original,
            replacement: replacement,
            language: entry.sourceLanguage
        ) { [weak self] in self?.rulesDidChange() }
    }

    @objc private func addRussianWord() { addSelectedWord(to: .russian) }
    @objc private func addEnglishWord() { addSelectedWord(to: .english) }

    private func addSelectedWord(to language: InputLanguage) {
        guard let entry = selectedEntry else { return }
        let word: String
        if entry.sourceLanguage == language {
            word = entry.original
        } else if entry.targetLanguage == language, let replacement = entry.replacement {
            word = replacement
        } else {
            word = entry.replacement ?? entry.original
        }
        store.addRule(kind: .accept, pattern: word, language: language) { [weak self] in
            self?.rulesDidChange()
        }
    }

    @objc private func deleteSelectedEntry() {
        guard let entry = selectedEntry else { return }
        store.deleteJournalEntry(id: entry.id) { [weak self] in self?.reload() }
    }

    @objc private func clearJournal() {
        let alert = NSAlert()
        alert.messageText = "Очистить дневник?"
        alert.informativeText = "Записи будут удалены. Пользовательские правила и словари сохранятся."
        alert.addButton(withTitle: "Очистить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.deleteAllJournalEntries { [weak self] in self?.reload() }
    }

    @objc private func addRule() {
        guard let draft = showRuleEditor(nil) else { return }
        store.addRule(
            kind: draft.kind,
            pattern: draft.pattern,
            replacement: draft.replacement,
            language: draft.language,
            applicationBundleIdentifier: draft.applicationBundleIdentifier
        ) { [weak self] in self?.rulesDidChange() }
    }

    @objc private func editSelectedRule() {
        guard let rule = selectedRule, let draft = showRuleEditor(rule) else { return }
        store.updateRule(UserRule(
            id: rule.id,
            kind: draft.kind,
            pattern: draft.pattern,
            replacement: draft.replacement,
            language: draft.language,
            applicationBundleIdentifier: draft.applicationBundleIdentifier,
            createdAt: rule.createdAt
        )) { [weak self] in self?.rulesDidChange() }
    }

    @objc private func deleteSelectedRule() {
        guard let rule = selectedRule else { return }
        let alert = NSAlert()
        alert.messageText = "Удалить правило для «\(rule.pattern)»?"
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.deleteRule(id: rule.id) { [weak self] in self?.rulesDidChange() }
    }

    @objc private func exportRules() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Shoev-Switcher-Rules.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(allRules).write(to: url, options: .atomic)
        } catch {
            showError("Не удалось экспортировать правила", error)
        }
    }

    @objc private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let rules = try decoder.decode([UserRule].self, from: Data(contentsOf: url))
            store.importRules(rules) { [weak self] imported in
                self?.rulesDidChange()
                self?.showMessage("Импортировано правил: \(imported)")
            }
        } catch {
            showError("Не удалось импортировать правила", error)
        }
    }

    private func rulesDidChange() {
        onRulesChanged()
        reload()
    }

    private func showRuleEditor(_ rule: UserRule?) -> RuleDraft? {
        let kindPopup = NSPopUpButton()
        for kind in [RuleKind.keep, .convert, .accept] {
            kindPopup.addItem(withTitle: kind.title)
            kindPopup.lastItem?.representedObject = kind.rawValue
        }
        if let kind = rule?.kind.rawValue,
           let index = kindPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == kind }) {
            kindPopup.selectItem(at: index)
        }

        let patternField = NSTextField(string: rule?.pattern ?? "")
        let replacementField = NSTextField(string: rule?.replacement ?? "")
        let languagePopup = NSPopUpButton()
        languagePopup.addItems(withTitles: ["Любой", "English", "Русский"])
        languagePopup.item(at: 1)?.representedObject = InputLanguage.english.rawValue
        languagePopup.item(at: 2)?.representedObject = InputLanguage.russian.rawValue
        if let language = rule?.language,
           let index = languagePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == language.rawValue }) {
            languagePopup.selectItem(at: index)
        }
        let appField = NSTextField(string: rule?.applicationBundleIdentifier ?? "")

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Тип:"), kindPopup],
            [NSTextField(labelWithString: "Слово:"), patternField],
            [NSTextField(labelWithString: "Замена:"), replacementField],
            [NSTextField(labelWithString: "Язык:"), languagePopup],
            [NSTextField(labelWithString: "Bundle ID:"), appField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 430, height: 150)

        let alert = NSAlert()
        alert.messageText = rule == nil ? "Новое правило" : "Изменить правило"
        alert.informativeText = "Bundle ID можно оставить пустым, чтобы правило работало во всех приложениях."
        alert.accessoryView = grid
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let pattern = patternField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty,
              let kindValue = kindPopup.selectedItem?.representedObject as? String,
              let kind = RuleKind(rawValue: kindValue) else { return nil }
        let replacementText = replacementField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = appField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return RuleDraft(
            kind: kind,
            pattern: pattern,
            replacement: replacementText.isEmpty ? nil : replacementText,
            language: (languagePopup.selectedItem?.representedObject as? String).flatMap(InputLanguage.init(rawValue:)),
            applicationBundleIdentifier: app.isEmpty ? nil : app
        )
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }

    private func showMessage(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }
}

private struct RuleDraft {
    let kind: RuleKind
    let pattern: String
    let replacement: String?
    let language: InputLanguage?
    let applicationBundleIdentifier: String?
}

private extension RuleKind {
    var title: String {
        switch self {
        case .keep: return "Не менять"
        case .convert: return "Всегда менять"
        case .accept: return "Словарь"
        }
    }
}

private struct JournalViewEntry {
    let value: JournalEntry
    let time: String
    let application: String
    let kind: String

    init(_ value: JournalEntry) {
        self.value = value
        time = Self.formatter.string(from: value.createdAt)
        application = value.applicationName ?? value.applicationBundleIdentifier ?? "—"
        switch value.kind {
        case .correction: kind = "Автоматически"
        case .manualCorrection: kind = "Вручную"
        case .typed: kind = "Набрано"
        case .undone: kind = "Отменено"
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
