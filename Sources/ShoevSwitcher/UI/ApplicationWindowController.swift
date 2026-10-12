import AppKit
import SwiftUI
import ServiceManagement

enum ApplicationPage: String, CaseIterable, Identifiable {
    case overview = "Обзор", switcher = "Switcher", spell = "Spell", journal = "Дневник"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .switcher: return "arrow.left.arrow.right"
        case .spell: return "text.badge.checkmark"
        case .journal: return "book.closed"
        }
    }
}

final class ApplicationModel: ObservableObject {
    @Published var page: ApplicationPage = .overview
    @Published private(set) var ready = false
    @Published private(set) var standaloneSpellRunning = false
    @Published private(set) var language = "—"
    @Published private(set) var diagnostic = "Исправления ещё не выполнялись."
    @Published private(set) var loginEnabled = false
    let monitor: KeyboardMonitor
    let sourceManager: InputSourceManager
    var preferencesChanged: () -> Void = {}
    var settingsView: () -> NSView = { NSView() }
    var journalView: () -> NSView = { NSView() }
    var reloadSettings: () -> Void = {}
    var reloadJournal: () -> Void = {}
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var preferenceObserver: NSObjectProtocol?
    private var fingerprint = ""

    init(monitor: KeyboardMonitor, sourceManager: InputSourceManager) {
        self.monitor = monitor
        self.sourceManager = sourceManager
        refresh()
        fingerprint = configurationFingerprint()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let current = self.configurationFingerprint()
                guard current != self.fingerprint else { return }
                self.fingerprint = current
                self.preferencesChanged()
                self.refresh()
            }
    }
    deinit {
        stopRefresh()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }
    func startRefresh() {
        refresh()
        guard timer == nil else { return }
        timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func stopRefresh() { timer?.invalidate(); timer = nil }
    func refresh() {
        ready = monitor.hasRequiredPermissions
        standaloneSpellRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.shoev.spell").isEmpty
        language = sourceManager.currentLanguage()?.title ?? "—"
        diagnostic = SpellInputDiagnostics.shared.latest?.rawValue ?? "Исправления ещё не выполнялись."
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func requestPermissions() { monitor.requestRequiredPermissions(); monitor.start(); refresh() }
    func stopStandaloneSpell() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.shoev.spell") { app.terminate() }
        refresh()
    }
    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSAlert(error: error).runModal() }
        refresh()
    }
    private func configurationFingerprint() -> String {
        let keys = [PreferenceKey.enabled, PreferenceKey.automaticCorrection, PreferenceKey.manualConversion,
            PreferenceKey.manualShortcut, PreferenceKey.phraseContext, PreferenceKey.applicationContext,
            PreferenceKey.rememberApplicationLayout, PreferenceKey.correctionNotifications,
            PreferenceKey.automaticLearning, PreferenceKey.undoAutomaticCorrection, PreferenceKey.journalEnabled,
            PreferenceKey.fullDiaryEnabled, PreferenceKey.hoverLanguageIndicator, PreferenceKey.englishInputSource,
            PreferenceKey.russianInputSource, PreferenceKey.excludedApplications, SpellPreferenceKey.enabled,
            SpellPreferenceKey.automaticCorrection, SpellPreferenceKey.automaticCapitalization,
            SpellPreferenceKey.automaticPunctuation, SpellPreferenceKey.journalEnabled,
            SpellPreferenceKey.minimumLength, SpellPreferenceKey.minimumScore, SpellPreferenceKey.excludedApplications]
        return keys.map { String(describing: UserDefaults.standard.object(forKey: $0)) }.joined(separator: "|")
    }
}

final class ApplicationWindowController: NSWindowController, NSWindowDelegate {
    let model: ApplicationModel
    init(model: ApplicationModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Shoev Switcher"
        window.minSize = NSSize(width: 960, height: 740)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: ApplicationView(model: model))
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func open(_ page: ApplicationPage = .overview) {
        model.page = page
        model.startRefresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model.stopRefresh() }
}

private enum Brand {
    static let gold = Color(red: 0.86, green: 0.74, blue: 0.49)
    static let platinum = Color(red: 0.89, green: 0.90, blue: 0.91)
    static let selection = Color(red: 0.23, green: 0.25, blue: 0.28)
    static let background = Color(red: 0.065, green: 0.075, blue: 0.085)
    static let panel = Color(red: 0.115, green: 0.13, blue: 0.145)
}

private struct ApplicationView: View {
    @ObservedObject var model: ApplicationModel
    @AppStorage(PreferenceKey.enabled) private var switcherEnabled = true
    @AppStorage(SpellPreferenceKey.enabled) private var spellEnabled = true
    @AppStorage(SpellPreferenceKey.automaticCorrection) private var correctWords = true
    @AppStorage(SpellPreferenceKey.automaticCapitalization) private var capitalize = true
    @AppStorage(SpellPreferenceKey.automaticPunctuation) private var punctuation = true
    @AppStorage(SpellPreferenceKey.journalEnabled) private var spellJournal = true
    @AppStorage(SpellPreferenceKey.minimumLength) private var minimumLength = 3
    @AppStorage(SpellPreferenceKey.minimumScore) private var minimumScore = 250
    @State private var exclusions = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Brand.gold.opacity(0.16))
            VStack(alignment: .leading, spacing: 22) {
                header
                switch model.page {
                case .overview: overview
                case .switcher: LegacyPane(view: model.settingsView()).onAppear { model.reloadSettings() }
                case .spell: spellSettings
                case .journal: LegacyPane(view: model.journalView()).onAppear { model.reloadJournal() }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Brand.background)
        .foregroundStyle(Brand.platinum)
        .tint(Brand.gold)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                Text("Shoev Switcher").font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            VStack(spacing: 7) {
                ForEach(ApplicationPage.allCases) { page in
                    Button { model.page = page } label: {
                        Label(page.rawValue, systemImage: page.symbol)
                            .font(.system(size: 14, weight: model.page == page ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
                            .foregroundStyle(model.page == page ? Brand.gold : Color.white.opacity(0.65))
                            .background(model.page == page ? Brand.selection : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(model.ready ? "Доступ готов" : "Нужны разрешения", systemImage: model.ready ? "checkmark.shield" : "exclamationmark.shield")
                    .foregroundStyle(model.ready ? Brand.gold : .orange).font(.system(size: 12))
                Text("RU / EN · Локальная обработка").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Created by Shoev Systems").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }.padding(22).frame(width: 200).background(Brand.panel.opacity(0.6))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.page == .overview ? "Shoev Switcher" : model.page.rawValue)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private var subtitle: String {
        switch model.page {
        case .overview: return "Правильная раскладка. Чистый текст. Одно приложение."
        case .switcher: return "Раскладки, контекст, горячие клавиши и исключения Switcher."
        case .spell: return "Независимые настройки орфографии, регистра и пунктуации."
        case .journal: return "Локальный дневник обоих модулей, правила и обучение."
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    moduleCard("Switcher", symbol: "arrow.left.arrow.right", text: "Исправляет слова в неверной раскладке и переключает русский и английский.", enabled: $switcherEnabled, page: .switcher)
                    moduleCard("Spell", symbol: "text.badge.checkmark", text: "Исправляет опечатки, заглавные буквы и помогает с русской пунктуацией.", enabled: $spellEnabled, page: .spell)
                }
                if model.standaloneSpellRunning { standaloneWarning }
                VStack(alignment: .leading, spacing: 14) {
                    Label("Одна система ввода", systemImage: "keyboard").font(.system(size: 16, weight: .semibold))
                    Text("Сначала проверяется раскладка, затем орфография. Одна база слов, один обработчик клавиатуры. Модули включаются независимо.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Label("Текущая раскладка", systemImage: "globe")
                        Spacer()
                        Text(model.language).foregroundStyle(Brand.gold)
                    }.font(.system(size: 13))
                    HStack {
                        Text("Запускать при входе в macOS")
                        Spacer()
                        Toggle("Автозапуск", isOn: Binding(get: { model.loginEnabled }, set: { _ in model.toggleLogin() }))
                            .labelsHidden().toggleStyle(.switch)
                    }.font(.system(size: 13))
                    if !model.ready {
                        Button("Выдать системные разрешения…") { model.requestPermissions() }.buttonStyle(.borderedProminent)
                    }
                }.card()
                Text("Пароли и защищённые поля не обрабатываются. Закрытие этого окна не останавливает приложение — кошка остаётся в строке меню.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private func moduleCard(_ name: String, symbol: String, text: String, enabled: Binding<Bool>, page: ApplicationPage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Brand.gold)
                Spacer()
                Toggle(name + " включён", isOn: enabled).labelsHidden().toggleStyle(.switch)
            }
            Text(name).font(.system(size: 23, weight: .semibold, design: .rounded))
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary).frame(minHeight: 54, alignment: .topLeading)
            Text(!enabled.wrappedValue ? "Выключен" : !model.ready ? "Ожидает разрешений" :
                page == .spell && model.standaloneSpellRunning ? "Пауза: отдельный Spell" : "Включён")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(enabled.wrappedValue ? Brand.gold : .secondary)
            Button("Настроить " + name) { model.page = page }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
    private var standaloneWarning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Запущен отдельный Shoev Spell", systemImage: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.gold)
            Text("Встроенный Spell временно не исправляет текст, чтобы два приложения не мешали друг другу. Отдельное приложение и его данные сохранены.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Завершить отдельный Spell") { model.stopStandaloneSpell() }.buttonStyle(.bordered)
        }.card()
    }
    private var spellSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Модуль Spell включён", isOn: $spellEnabled).toggleStyle(.switch).font(.system(size: 16, weight: .semibold))
                if model.standaloneSpellRunning { standaloneWarning }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Исправление текста").font(.system(size: 16, weight: .semibold))
                    Toggle("Исправлять русские и английские опечатки", isOn: $correctWords)
                    Toggle("Заглавная буква в начале предложения", isOn: $capitalize)
                    Toggle("Помогать с русской пунктуацией", isOn: $punctuation)
                    Toggle("Сохранять исправления Spell в общем дневнике", isOn: $spellJournal)
                    Divider()
                    Stepper("Минимальная длина слова: \(minimumLength)", value: $minimumLength, in: 3...8)
                    Stepper("Порог уверенности: \(minimumScore)", value: $minimumScore, in: 250...800, step: 25)
                    Text("Повышай порог, если появляются ложные исправления. Enter и Tab всегда остаются действиями редактора.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.card().disabled(!spellEnabled)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Исключённые приложения Spell").font(.system(size: 16, weight: .semibold))
                    Text("Bundle ID, по одному в строке. Эти исключения не меняют настройки Switcher.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    TextEditor(text: $exclusions).font(.system(size: 12, design: .monospaced)).frame(height: 105)
                        .padding(8).background(Brand.background).clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Исключённые приложения Spell")
                    Button("Сохранить исключения") {
                        let ids = exclusions.split(whereSeparator: \.isNewline)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        UserDefaults.standard.set(Array(Set(ids)).sorted(), forKey: SpellPreferenceKey.excludedApplications)
                        model.preferencesChanged()
                    }.buttonStyle(.bordered)
                }.card()
                Text(model.diagnostic).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.onAppear {
            exclusions = (UserDefaults.standard.stringArray(forKey: SpellPreferenceKey.excludedApplications) ?? []).joined(separator: "\n")
        }
    }
}

private struct LegacyPane: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
private extension View {
    func card() -> some View {
        self.padding(20).background(Brand.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gold.opacity(0.12), lineWidth: 1))
    }
}
