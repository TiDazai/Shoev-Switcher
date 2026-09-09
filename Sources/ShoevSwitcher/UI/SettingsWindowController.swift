import AppKit

final class SettingsWindowController: NSWindowController {
    private let monitor: KeyboardMonitor
    private let sourceManager: InputSourceManager
    private let onSaved: () -> Void

    private let englishPopup = NSPopUpButton()
    private let russianPopup = NSPopUpButton()
    private let exclusionsView = NSTextView()
    private let permissionLabel = NSTextField(labelWithString: "")

    init(monitor: KeyboardMonitor, sourceManager: InputSourceManager, onSaved: @escaping () -> Void) {
        self.monitor = monitor
        self.sourceManager = sourceManager
        self.onSaved = onSaved
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
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

        let title = NSTextField(labelWithString: "Русская и английская раскладки")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.maximumNumberOfLines = 2

        let permissionButton = NSButton(
            title: "Проверить разрешения",
            target: self,
            action: #selector(requestPermissions)
        )

        let exclusionsLabel = NSTextField(labelWithString: "Не исправлять в этих приложениях (Bundle ID, по одному в строке):")
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = exclusionsView
        exclusionsView.isRichText = false
        exclusionsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "English:"), englishPopup],
            [NSTextField(labelWithString: "Русский:"), russianPopup]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 8
        grid.columnSpacing = 12

        let saveButton = NSButton(title: "Сохранить", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let note = NSTextField(wrappingLabelWithString: "Двойное нажатие правого Shift принудительно конвертирует текущее или последнее слово. Парольные поля и Secure Event Input всегда игнорируются.")
        note.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            title,
            grid,
            permissionLabel,
            permissionButton,
            exclusionsLabel,
            scrollView,
            note,
            saveButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        englishPopup.translatesAutoresizingMaskIntoConstraints = false
        russianPopup.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        saveButton.alignment = .center

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            englishPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            russianPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 135)
        ])
    }

    private func reloadValues() {
        sourceManager.reloadSources()
        populate(englishPopup, sources: sourceManager.allSources(for: .english), selected: sourceManager.englishSource)
        populate(russianPopup, sources: sourceManager.allSources(for: .russian), selected: sourceManager.russianSource)

        let exclusions = UserDefaults.standard.stringArray(forKey: PreferenceKey.excludedApplications) ?? []
        exclusionsView.string = exclusions.sorted().joined(separator: "\n")
        permissionLabel.stringValue = monitor.hasRequiredPermissions
            ? "Системные разрешения выданы. Перехват и исправление клавиатуры доступны."
            : "Нужны разрешения Input Monitoring и Accessibility. После выдачи разрешений приложение может потребоваться перезапустить."
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

    @objc private func requestPermissions() {
        monitor.requestRequiredPermissions()
        monitor.start()
        reloadValues()
    }

    @objc private func save() {
        let defaults = UserDefaults.standard
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
}
