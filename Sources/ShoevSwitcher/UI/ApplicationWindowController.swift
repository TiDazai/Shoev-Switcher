import AppKit
import SwiftUI
import ServiceManagement

enum ApplicationPage: String, CaseIterable, Identifiable {
    case overview = "Обзор", switcher = "Switcher", spell = "Spell", journal = "Журнал", diary = "Дневник", dictionary = "Словарь"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .switcher: return "arrow.left.arrow.right"
        case .spell: return "text.badge.checkmark"
        case .journal: return "clock.arrow.circlepath"
        case .diary: return "book.closed"
        case .dictionary: return "character.book.closed"
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
    let knowledge: KnowledgeModel?
    var preferencesChanged: () -> Void = {}
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var preferenceObserver: NSObjectProtocol?
    private var fingerprint = ""

    init(monitor: KeyboardMonitor, sourceManager: InputSourceManager, knowledge: KnowledgeModel? = nil) {
        self.monitor = monitor
        self.sourceManager = sourceManager
        self.knowledge = knowledge
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
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(Brand.background)
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
        if [.journal, .diary, .dictionary].contains(page) { model.knowledge?.refresh(includeJournal: page == .journal) }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model.stopRefresh() }
}

enum Brand {
    static let ink = Color(red: 0.16, green: 0.18, blue: 0.21)
    static let accent = Color(red: 0.43, green: 0.32, blue: 0.15)
    static let gold = Color(red: 0.76, green: 0.64, blue: 0.40)
    static let secondary = Color(red: 0.34, green: 0.37, blue: 0.42)
    static let selection = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let background = Color(red: 0.92, green: 0.93, blue: 0.95)
    static let panel = Color(red: 0.965, green: 0.975, blue: 0.988)
    static let panelHighlight = Color.white
    static let sidebar = Color(red: 0.90, green: 0.915, blue: 0.94)
    static let edge = Color(red: 0.60, green: 0.65, blue: 0.72)
    static let warning = Color(red: 0.61, green: 0.32, blue: 0.11)
    // Decode once, not each time the status model refreshes. No animation or drawing loop.
    static let surfaceImage = Bundle.module.url(forResource: "MetalSurface", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
    static let catImage = Bundle.module.url(forResource: "BrandCat", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
}

struct MetalBackground: View {
    var tint: Color = Brand.background
    var textureOpacity: Double = 0.3
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                tint
                if let image = Brand.surfaceImage {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(textureOpacity)
                }
            }.clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct MetalCatLogo: View {
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        if let cat = Brand.catImage {
            Image(nsImage: cat).resizable().scaledToFit()
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
            .accessibilityHidden(true)
        }
    }
}

private struct ApplicationView: View {
    @ObservedObject var model: ApplicationModel
    @AppStorage(PreferenceKey.enabled) private var switcherEnabled = true
    @AppStorage(PreferenceKey.automaticCorrection) private var automaticLayout = true
    @AppStorage(PreferenceKey.manualConversion) private var manualConversion = true
    @AppStorage(PreferenceKey.manualShortcut) private var manualShortcut = ManualShortcut.rightShift.rawValue
    @AppStorage(PreferenceKey.phraseContext) private var phraseContext = true
    @AppStorage(PreferenceKey.applicationContext) private var applicationContext = true
    @AppStorage(PreferenceKey.rememberApplicationLayout) private var layoutMemory = false
    @AppStorage(PreferenceKey.automaticLearning) private var learning = true
    @AppStorage(PreferenceKey.undoAutomaticCorrection) private var undoCorrection = true
    @AppStorage(PreferenceKey.hoverLanguageIndicator) private var hoverFlag = true
    @AppStorage(PreferenceKey.correctionNotifications) private var correctionNotifications = true
    @AppStorage(PreferenceKey.journalEnabled) private var switcherJournal = true
    @AppStorage(PreferenceKey.fullDiaryEnabled) private var fullDiary = false
    @AppStorage(PreferenceKey.englishInputSource) private var englishInputSource = ""
    @AppStorage(PreferenceKey.russianInputSource) private var russianInputSource = ""
    @AppStorage(SpellPreferenceKey.enabled) private var spellEnabled = true
    @AppStorage(SpellPreferenceKey.automaticCorrection) private var correctWords = true
    @AppStorage(SpellPreferenceKey.automaticCapitalization) private var capitalize = true
    @AppStorage(SpellPreferenceKey.automaticPunctuation) private var punctuation = true
    @AppStorage(SpellPreferenceKey.journalEnabled) private var spellJournal = true
    @AppStorage(SpellPreferenceKey.minimumLength) private var minimumLength = 3
    @AppStorage(SpellPreferenceKey.minimumScore) private var minimumScore = 250
    @State private var exclusions = ""
    @State private var switcherExclusions = ""
    @FocusState private var focusedPage: ApplicationPage?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Brand.edge.opacity(0.35))
            VStack(alignment: .leading, spacing: 22) {
                header
                switch model.page {
                case .overview: overview
                case .switcher: switcherSettings
                case .spell: spellSettings
                case .journal, .diary, .dictionary:
                    if let knowledge = model.knowledge { KnowledgePageView(page: model.page, knowledge: knowledge) }
                    else { Text("Не удалось открыть личную базу. Проверь доступ к Application Support.").foregroundStyle(Brand.warning) }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MetalBackground())
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                MetalCatLogo(width: 48, height: 48)
                Text("Shoev Switcher").font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            VStack(spacing: 7) {
                ForEach(ApplicationPage.allCases) { page in
                    Button { model.page = page } label: {
                        Label(page.rawValue, systemImage: page.symbol)
                            .font(.system(size: 14, weight: model.page == page ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
                            .foregroundStyle(model.page == page ? Brand.accent : Brand.secondary)
                            .background {
                                if model.page == page {
                                    RoundedRectangle(cornerRadius: 12).fill(
                                        LinearGradient(colors: [Brand.selection, Brand.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                                focusedPage == page ? Brand.accent.opacity(0.8) : model.page == page ? Brand.gold.opacity(0.65) : Color.clear,
                                lineWidth: 1))
                    }.buttonStyle(.plain).focused($focusedPage, equals: page).focusEffectDisabled()
                        .accessibilityAddTraits(model.page == page ? .isSelected : [])
                }
            }
            Spacer()
            Text("Created by Shoev Systems").font(.system(size: 11)).foregroundStyle(Brand.secondary)
        }.padding(22).frame(width: 232)
            .background(MetalBackground(tint: Brand.sidebar, textureOpacity: 0.08))
    }

    private var header: some View {
        HStack(spacing: 20) {
            Text(model.page == .overview ? "Shoev Switcher" : model.page.rawValue)
                .font(.system(size: 30, weight: .medium)).tracking(-0.5)
            Spacer(minLength: 0)
            if model.page == .overview {
                MetalCatLogo(width: 82, height: 98)
            }
        }
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    moduleCard("Switcher", symbol: "arrow.left.arrow.right", enabled: $switcherEnabled, page: .switcher)
                    moduleCard("Spell", symbol: "text.badge.checkmark", enabled: $spellEnabled, page: .spell)
                }
                if model.standaloneSpellRunning { standaloneWarning }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Текущая раскладка", systemImage: "globe")
                        Spacer()
                        Text(model.language).foregroundStyle(Brand.accent)
                    }.font(.system(size: 13))
                    HStack {
                        Text("Запускать при входе в macOS")
                        Spacer()
                        Toggle("Автозапуск", isOn: Binding(get: { model.loginEnabled }, set: { _ in model.toggleLogin() }))
                            .labelsHidden().toggleStyle(.switch).tint(Brand.gold)
                    }.font(.system(size: 13))
                    if !model.ready {
                        Button("Выдать системные разрешения…") { model.requestPermissions() }.buttonStyle(.borderedProminent)
                    }
                }.card()
            }
        }
    }
    private func moduleCard(_ name: String, symbol: String, enabled: Binding<Bool>, page: ApplicationPage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Brand.accent).frame(width: 32, height: 32)
                Spacer()
                Toggle(name + " включён", isOn: enabled).labelsHidden().toggleStyle(.switch).tint(Brand.gold)
            }
            Text(name).font(.system(size: 23, weight: .medium))
            Button("Настроить " + name) { model.page = page }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
    private var standaloneWarning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Запущен отдельный Shoev Spell", systemImage: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.accent)
            Button("Завершить отдельный Spell") { model.stopStandaloneSpell() }.buttonStyle(.bordered)
        }.card()
    }
    private var spellSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Модуль Spell включён", isOn: $spellEnabled).toggleStyle(.switch).tint(Brand.gold).font(.system(size: 16, weight: .semibold))
                if model.standaloneSpellRunning { standaloneWarning }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Исправление текста").font(.system(size: 16, weight: .semibold))
                    Toggle("Исправлять русские и английские опечатки", isOn: $correctWords)
                    Toggle("Заглавная буква в начале предложения", isOn: $capitalize)
                    Toggle("Помогать с русской пунктуацией", isOn: $punctuation)
                    Toggle("Сохранять исправления Spell в журнале", isOn: $spellJournal)
                    Toggle("Самообучение обоих модулей по подтверждённым повторениям", isOn: $learning)
                    Divider()
                    Stepper("Минимальная длина слова: \(minimumLength)", value: $minimumLength, in: 3...8)
                    Stepper("Порог уверенности: \(minimumScore)", value: $minimumScore, in: 250...800, step: 25)
                }.card().disabled(!spellEnabled)
                exclusionsCard("Spell", text: $exclusions, key: SpellPreferenceKey.excludedApplications)
            }
        }.onAppear {
            exclusions = (UserDefaults.standard.stringArray(forKey: SpellPreferenceKey.excludedApplications) ?? []).joined(separator: "\n")
        }
    }

    private var switcherSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Модуль Switcher включён", isOn: $switcherEnabled)
                    .toggleStyle(.switch).tint(Brand.gold).font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 16) {
                    Text("Исправление раскладки").font(.system(size: 16, weight: .semibold))
                    Toggle("Исправлять раскладку автоматически", isOn: $automaticLayout)
                    Toggle("Учитывать предыдущие слова и частые фразы", isOn: $phraseContext).disabled(!automaticLayout)
                    Toggle("Учитывать привычный язык каждого приложения", isOn: $applicationContext).disabled(!automaticLayout)
                    Toggle("Ручная конвертация двойным Shift", isOn: $manualConversion)
                    Picker("Горячая клавиша", selection: $manualShortcut) {
                        ForEach(ManualShortcut.allCases, id: \.rawValue) { shortcut in
                            Text(shortcut.title).tag(shortcut.rawValue)
                        }
                    }.disabled(!manualConversion)
                }.card().disabled(!switcherEnabled)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Интерфейс и поведение").font(.system(size: 16, weight: .semibold))
                    Toggle("Запоминать раскладку для каждого приложения", isOn: $layoutMemory)
                    Toggle("Отменять автоисправление клавишей Backspace", isOn: $undoCorrection).disabled(!automaticLayout)
                    Toggle("Показывать флаг рядом с курсором мыши", isOn: $hoverFlag)
                    Toggle("Показывать короткое уведомление об исправлении", isOn: $correctionNotifications)
                }.card().disabled(!switcherEnabled)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Самообучение и журнал").font(.system(size: 16, weight: .semibold))
                    Toggle("Самообучение обоих модулей по подтверждённым повторениям", isOn: $learning)
                    Toggle("Сохранять исправления Switcher в журнале", isOn: $switcherJournal).disabled(!switcherEnabled)
                    Toggle("Сохранять все завершённые слова", isOn: $fullDiary).disabled(!switcherEnabled || !switcherJournal)
                }.card()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Источники ввода").font(.system(size: 16, weight: .semibold))
                    sourcePicker("English", language: .english, selection: $englishInputSource)
                    sourcePicker("Русский", language: .russian, selection: $russianInputSource)
                }.card()
                exclusionsCard("Switcher", text: $switcherExclusions, key: PreferenceKey.excludedApplications)
                if !model.ready {
                    Button("Выдать системные разрешения…") { model.requestPermissions() }.buttonStyle(.bordered)
                }
            }
        }.onAppear {
            switcherExclusions = (UserDefaults.standard.stringArray(forKey: PreferenceKey.excludedApplications) ?? []).joined(separator: "\n")
        }
    }

    private func sourcePicker(_ title: String, language: InputLanguage, selection: Binding<String>) -> some View {
        let sources = model.sourceManager.allSources(for: language)
        return Picker(title, selection: selection) {
            if !sources.contains(where: { $0.identifier == selection.wrappedValue }) {
                Text(sources.isEmpty ? "Добавьте раскладку в macOS" : "Автоматически").tag(selection.wrappedValue)
            }
            ForEach(sources, id: \.identifier) { source in Text(source.name).tag(source.identifier) }
        }
    }

    private func exclusionsCard(_ module: String, text: Binding<String>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Исключённые приложения " + module).font(.system(size: 16, weight: .semibold))
            TextEditor(text: text).font(.system(size: 12, design: .monospaced)).frame(height: 105)
                .padding(8).background(Brand.background).clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Исключённые приложения " + module)
            Button("Сохранить исключения") {
                let ids = text.wrappedValue.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                UserDefaults.standard.set(Array(Set(ids)).sorted(), forKey: key)
                model.preferencesChanged()
            }.buttonStyle(.bordered)
        }.card()
    }
}

extension View {
    func card() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(LinearGradient(colors: [Brand.panelHighlight, Brand.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                LinearGradient(colors: [Brand.edge.opacity(0.38), Brand.edge.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.065), radius: 8, x: 0, y: 4)
    }
}
