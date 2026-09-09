import AppKit

final class JournalWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: JournalStore
    private let onRulesChanged: () -> Void
    private let tableView = NSTableView()
    private var entries: [JournalViewEntry] = []

    init(store: JournalStore, onRulesChanged: @escaping () -> Void) {
        self.store = store
        self.onRulesChanged = onRulesChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Дневник Shoev Switcher"
        window.center()
        super.init(window: window)
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        store.recentEntries { [weak self] entries in
            self?.entries = entries.map(JournalViewEntry.init)
            self?.tableView.reloadData()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count, let identifier = tableColumn?.identifier else { return nil }
        let entry = entries[row]
        let text: String
        switch identifier.rawValue {
        case "time": text = entry.time
        case "app": text = entry.application
        case "original": text = entry.value.original
        case "replacement": text = entry.value.replacement ?? "—"
        default: text = entry.kind
        }
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text
        return field
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        addColumn("time", title: "Время", width: 125)
        addColumn("app", title: "Приложение", width: 135)
        addColumn("original", title: "Было", width: 170)
        addColumn("replacement", title: "Стало", width: 170)
        addColumn("kind", title: "Действие", width: 110)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let keepButton = NSButton(title: "Никогда не менять", target: self, action: #selector(addKeepRule))
        let convertButton = NSButton(title: "Всегда менять", target: self, action: #selector(addConvertRule))
        let russianButton = NSButton(title: "+ в русский словарь", target: self, action: #selector(addRussianWord))
        let englishButton = NSButton(title: "+ в English dictionary", target: self, action: #selector(addEnglishWord))
        let clearButton = NSButton(title: "Очистить дневник", target: self, action: #selector(clearJournal))

        let buttons = NSStackView(views: [keepButton, convertButton, russianButton, englishButton, NSView(), clearButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func addColumn(_ identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private var selectedEntry: JournalEntry? {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return nil }
        return entries[row].value
    }

    @objc private func addKeepRule() {
        guard let entry = selectedEntry else { return }
        store.addRule(kind: .keep, pattern: entry.original) { [weak self] in
            self?.onRulesChanged()
        }
    }

    @objc private func addConvertRule() {
        guard let entry = selectedEntry, let replacement = entry.replacement else { return }
        store.addRule(kind: .convert, pattern: entry.original, replacement: replacement) { [weak self] in
            self?.onRulesChanged()
        }
    }

    @objc private func addRussianWord() {
        addSelectedWord(to: .russian)
    }

    @objc private func addEnglishWord() {
        addSelectedWord(to: .english)
    }

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
            self?.onRulesChanged()
        }
    }

    @objc private func clearJournal() {
        let alert = NSAlert()
        alert.messageText = "Очистить дневник?"
        alert.informativeText = "Все записи будут удалены. Пользовательские правила и словари сохранятся."
        alert.addButton(withTitle: "Очистить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.deleteAllJournalEntries { [weak self] in self?.reload() }
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
