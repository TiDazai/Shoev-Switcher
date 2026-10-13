import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name { static let shoevKnowledgeChanged = Notification.Name("ShoevKnowledgeChanged") }

final class KnowledgeModel: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var rules: [UserRule] = []
    @Published private(set) var words: [PersonalWord] = []
    @Published private(set) var observations: [AdaptiveObservation] = []
    @Published var error: String?
    let store: JournalStore
    private let changed: () -> Void
    init(store: JournalStore, changed: @escaping () -> Void) { self.store = store; self.changed = changed }
    func refresh(includeJournal: Bool = false) {
        if includeJournal { store.recentEntries(limit: 1000) { [weak self] in self?.entries = $0 } }
        store.rules { [weak self] in self?.rules = $0 }
        store.personalWords { [weak self] in self?.words = $0 }
        store.observations { [weak self] in self?.observations = $0 }
    }
    private func didChange() { changed(); refresh() }
    func save(_ rule: UserRule, isNew: Bool) {
        if isNew {
            store.addRule(kind: rule.kind, pattern: rule.pattern, replacement: rule.replacement,
                language: rule.language, applicationBundleIdentifier: rule.applicationBundleIdentifier,
                module: rule.module, origin: .manual, targetLanguage: rule.targetLanguage) { [weak self] in self?.didChange() }
        } else { store.updateRule(rule) { [weak self] in self?.didChange() } }
    }
    func remove(_ rule: UserRule) { store.deleteRule(id: rule.id) { [weak self] in self?.didChange() } }
    func toggle(_ rule: UserRule) { var copy = rule; copy.enabled = !copy.isEnabled; save(copy, isNew: false) }
    func addWord(_ word: String, language: InputLanguage) {
        store.addPersonalWord(word, language: language) { [weak self] saved in
            guard let self else { return }
            if saved { didChange() } else { error = "Не удалось сохранить слово. Проверь язык и используй буквы, дефис или апостроф." }
        }
    }
    func removeWord(_ word: PersonalWord) { store.deletePersonalWord(id: word.id) { [weak self] in self?.didChange() } }
    func removeEntry(_ entry: JournalEntry) { store.deleteJournalEntry(id: entry.id) { [weak self] in self?.refresh(includeJournal: true) } }
    func clearJournal() {
        let alert = NSAlert(); alert.messageText = "Очистить журнал?"
        alert.informativeText = "История событий будет удалена. Дневник правил и личные слова останутся."
        alert.addButton(withTitle: "Очистить журнал"); alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn { store.deleteAllJournalEntries { [weak self] in self?.refresh(includeJournal: true) } }
    }
    func rule(from entry: JournalEntry, keep: Bool) -> UserRule {
        UserRule(id: 0, kind: keep ? .keep : .convert, pattern: entry.original,
            replacement: keep ? nil : entry.replacement, language: entry.sourceLanguage,
            applicationBundleIdentifier: entry.applicationBundleIdentifier, createdAt: Date(),
            module: entry.kind == .spelling ? .spell : .switcher, origin: .manual, enabled: true,
            targetLanguage: entry.targetLanguage)
    }
    func exportDiary() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Shoev-Personal-Knowledge.json"
        panel.message = "Экспорт содержит личные слова и правила в открытом JSON. Храни файл в безопасном месте."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(KnowledgeExport(format: 1, rules: rules, words: words)).write(to: url, options: .atomic)
        } catch { self.error = "Не удалось экспортировать личные данные." }
    }
    func importDiary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8 * 1024 * 1024 else { error = "Файл больше 8 МБ."; return }
            let data = try Data(contentsOf: url)
            let payload: KnowledgeExport
            if let current = try? decoder.decode(KnowledgeExport.self, from: data) { payload = current }
            else { payload = KnowledgeExport(format: 1, rules: try decoder.decode([UserRule].self, from: data), words: []) }
            guard payload.format == 1 else { error = "Неизвестная версия формата."; return }
            store.importRules(payload.rules) { [weak self] _ in
                guard let self else { return }
                self.store.importPersonalWords(payload.words) { [weak self] in self?.didChange() }
            }
        } catch { self.error = "Не удалось прочитать личные правила и слова." }
    }
}

struct KnowledgeExport: Codable { let format: Int; let rules: [UserRule]; let words: [PersonalWord] }

final class DictionaryBrowserModel: ObservableObject {
    @Published var language: InputLanguage = .russian
    @Published var query = ""
    @Published var source: DictionarySourceFilter = .all
    @Published private(set) var page = DictionaryPage(rows: [], hasNext: false, builtinCount: 0, personalCount: 0)
    @Published private(set) var loading = false
    @Published private(set) var pageNumber = 1
    private let catalog: DictionaryCatalog
    private var cursors: [String?] = [nil]
    private var requestID = UUID()
    private var work: DispatchWorkItem?
    init(catalog: DictionaryCatalog = DictionaryCatalog()) { self.catalog = catalog }
    func reload(words: [PersonalWord], reset: Bool = true, debounce: Bool = false) {
        work?.cancel(); requestID = UUID(); let id = requestID
        if reset { cursors = [nil]; pageNumber = 1 }
        loading = true
        let cursor = cursors.last ?? nil
        let task = DispatchWorkItem { [weak self] in
            guard let self, requestID == id else { return }
            catalog.page(language: language, prefix: query, after: cursor, source: source, personal: words) { [weak self] page in
                guard let self, requestID == id else { return }
                self.page = page; loading = false
            }
        }
        work = task
        if debounce { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task) } else { task.perform() }
    }
    func next(words: [PersonalWord]) {
        guard !loading, page.hasNext, let cursor = page.rows.last?.word else { return }
        cursors.append(cursor); pageNumber += 1; reload(words: words, reset: false)
    }
    func previous(words: [PersonalWord]) {
        guard !loading, cursors.count > 1 else { return }
        cursors.removeLast(); pageNumber -= 1; reload(words: words, reset: false)
    }
}

private struct RuleDraft: Identifiable { let id = UUID(); let rule: UserRule; let isNew: Bool }

struct KnowledgePageView: View {
    let page: ApplicationPage
    @ObservedObject var knowledge: KnowledgeModel
    @StateObject private var dictionary = DictionaryBrowserModel()
    @State private var journalQuery = ""
    @State private var diaryQuery = ""
    @State private var journalModule = "all"
    @State private var journalOutcome = "all"
    @State private var journalSelection: Int64?
    @State private var ruleSelection: Int64?
    @State private var wordSelection: String?
    @State private var draft: RuleDraft?
    @State private var addingWord = false
    @State private var showObservations = false
    @AppStorage(PreferenceKey.automaticLearning) private var learning = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if page == .journal { journal }
            else if page == .diary { diary }
            else { dictionaryView }
        }
        .onAppear { knowledge.refresh(includeJournal: page == .journal); if page == .dictionary { dictionary.reload(words: knowledge.words) } }
        .onChange(of: page) { _, value in if value == .dictionary { dictionary.reload(words: knowledge.words) } }
        .onChange(of: knowledge.words) { _, words in if page == .dictionary { dictionary.reload(words: words) } }
        .onReceive(NotificationCenter.default.publisher(for: .shoevKnowledgeChanged)) { _ in
            if NSApp.keyWindow?.isVisible == true { knowledge.refresh(includeJournal: page == .journal) }
        }
        .sheet(item: $draft) { item in RuleEditorView(rule: item.rule, isNew: item.isNew) { rule in knowledge.save(rule, isNew: item.isNew) } }
        .sheet(isPresented: $addingWord) { WordEditorView(language: dictionary.language) { word, language in knowledge.addWord(word, language: language) } }
        .alert("Личные данные", isPresented: Binding(get: { knowledge.error != nil }, set: { if !$0 { knowledge.error = nil } })) {
            Button("ОК") { knowledge.error = nil }
        } message: { Text(knowledge.error ?? "") }
    }

    private var journalRows: [JournalEntry] {
        knowledge.entries.filter { entry in
            let module = entry.kind == .spelling ? "spell" : "switcher"
            return (journalModule == "all" || journalModule == module)
                && (journalOutcome == "all" || entry.outcome?.rawValue == journalOutcome)
                && (journalQuery.isEmpty || [entry.original, entry.replacement ?? "", entry.applicationName ?? "", entry.applicationBundleIdentifier ?? ""]
                    .joined(separator: " ").localizedCaseInsensitiveContains(journalQuery))
        }
    }
    private var selectedEntry: JournalEntry? { journalRows.first { $0.id == journalSelection } }

    private var journal: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Поиск по слову или приложению", text: $journalQuery).textFieldStyle(.roundedBorder)
                Picker("Модуль", selection: $journalModule) {
                    Text("Все модули").tag("all"); Text("Switcher").tag("switcher"); Text("Spell").tag("spell")
                }.labelsHidden().frame(width: 130)
                Picker("Статус", selection: $journalOutcome) {
                    Text("Все статусы").tag("all")
                    ForEach(FeedbackOutcome.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().frame(width: 185)
                Button { knowledge.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Обновить")
            }
            Table(journalRows, selection: $journalSelection) {
                TableColumn("Время") { Text($0.createdAt.formatted(date: .numeric, time: .shortened)).font(.system(size: 11)) }.width(min: 100, ideal: 125)
                TableColumn("Было", value: \.original)
                TableColumn("Стало") { Text($0.replacement ?? "—") }
                TableColumn("Статус") { Text($0.outcome?.title ?? "Ранее записано").font(.system(size: 11)).foregroundStyle($0.outcome == .rejected || $0.outcome == .edited ? Brand.warning : Brand.accent) }.width(min: 110, ideal: 155)
                TableColumn("Приложение") { Text($0.applicationName ?? "—").font(.system(size: 11)) }
            }
            HStack {
                Button("Не исправлять") { if let entry = selectedEntry { draft = RuleDraft(rule: knowledge.rule(from: entry, keep: true), isNew: true) } }.disabled(selectedEntry == nil)
                Button("Личное правило…") { if let entry = selectedEntry { draft = RuleDraft(rule: knowledge.rule(from: entry, keep: false), isNew: true) } }.disabled(selectedEntry?.replacement == nil)
                Button("Удалить событие") { if let entry = selectedEntry { knowledge.removeEntry(entry) } }.disabled(selectedEntry == nil)
                Spacer(); Text("Последние \(knowledge.entries.count) событий").font(.system(size: 11)).foregroundStyle(Brand.secondary)
                Button("Очистить…", role: .destructive) { knowledge.clearJournal() }
            }.font(.system(size: 12))
        }
    }

    private var diaryRows: [UserRule] {
        knowledge.rules.filter { $0.kind != .accept && (diaryQuery.isEmpty || [$0.pattern, $0.replacement ?? "", $0.applicationBundleIdentifier ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(diaryQuery)) }
    }
    private var selectedRule: UserRule? { diaryRows.first { $0.id == ruleSelection } }
    private var diary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Поиск личного правила", text: $diaryQuery).textFieldStyle(.roundedBorder)
                Button("Добавить правило…") { draft = RuleDraft(rule: UserRule(id: 0, kind: .keep, pattern: "", replacement: nil,
                    language: .russian, applicationBundleIdentifier: nil, createdAt: Date(), origin: .manual), isNew: true) }
                Button("Импорт…") { knowledge.importDiary() }
                Button("Экспорт…") { knowledge.exportDiary() }
            }
            Toggle("Самообучение обоих модулей", isOn: $learning).toggleStyle(.switch).tint(Brand.gold)
            Table(diaryRows, selection: $ruleSelection) {
                TableColumn("Слово / фраза", value: \.pattern)
                TableColumn("Действие") { Text($0.kind == .convert ? "→ " + ($0.replacement ?? "—") : "Не менять") }
                TableColumn("Модуль") { Text($0.module?.title ?? "Оба").font(.system(size: 12)) }.width(min: 65, ideal: 75)
                TableColumn("Источник") { Text(($0.origin ?? .manual).title).foregroundStyle($0.origin == .learning ? Brand.accent : Brand.ink).font(.system(size: 12)) }
                TableColumn("Состояние") { Text($0.isEnabled ? "Включено" : "Приостановлено").foregroundStyle($0.isEnabled ? Brand.accent : Brand.secondary).font(.system(size: 12)) }
                TableColumn("Область") { Text($0.applicationBundleIdentifier ?? "Все приложения").font(.system(size: 11)).help($0.applicationBundleIdentifier ?? "Все приложения") }
            }
            HStack {
                Button("Изменить…") { if let rule = selectedRule { draft = RuleDraft(rule: rule, isNew: false) } }.disabled(selectedRule == nil)
                Button(selectedRule?.isEnabled == false ? "Включить" : "Приостановить") { if let rule = selectedRule { knowledge.toggle(rule) } }.disabled(selectedRule == nil)
                Button("Удалить правило", role: .destructive) { if let rule = selectedRule { knowledge.remove(rule) } }.disabled(selectedRule == nil)
                Spacer(); Button(showObservations ? "Скрыть наблюдения" : "Наблюдения обучения") { showObservations.toggle() }
            }.font(.system(size: 12))
            if showObservations {
                VStack(alignment: .leading, spacing: 7) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(knowledge.observations) { entry in
                                HStack {
                                    Text(entry.pattern + (entry.replacement.map { " → " + $0 } ?? " · не менять"))
                                    Spacer(); Text(entry.module.title + " · \(entry.confirmations)/3" + (entry.learnedRuleID == nil ? " · наблюдение" : " · в дневнике")).foregroundStyle(Brand.accent)
                                }.font(.system(size: 12))
                            }
                            if knowledge.observations.isEmpty { Text("Подтверждённых наблюдений пока нет.").foregroundStyle(Brand.secondary) }
                        }
                    }.frame(maxHeight: 140)
                }.card()
            }
        }
    }

    private var dictionaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Язык", selection: $dictionary.language) { Text("Русский").tag(InputLanguage.russian); Text("English").tag(InputLanguage.english) }
                    .pickerStyle(.segmented).frame(width: 230)
                Spacer()
                Text("Встроено: \(dictionary.page.builtinCount.formatted()) · личных: \(dictionary.page.personalCount.formatted())").font(.system(size: 12)).foregroundStyle(Brand.secondary)
                Button("Добавить слово…") { addingWord = true }
            }
            HStack {
                TextField("Поиск по началу слова", text: $dictionary.query).textFieldStyle(.roundedBorder)
                Picker("Источник", selection: $dictionary.source) { ForEach(DictionarySourceFilter.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().frame(width: 160)
                if dictionary.loading { ProgressView().controlSize(.small) }
            }
            Table(dictionary.page.rows, selection: $wordSelection) {
                TableColumn("Слово") { row in
                    HStack { if !row.personal.isEmpty { Image(systemName: "star.fill").foregroundStyle(Brand.accent).font(.system(size: 10)) }
                        Text(row.word).fontWeight(row.personal.isEmpty ? .regular : .semibold) }
                }
                TableColumn("Источник") { row in
                    Text(row.personal.first?.origin.title ?? "Встроенный словарь").font(.system(size: 12))
                }
                TableColumn("База") { Text($0.builtin ? "Есть во встроенной" : "Личное дополнение").font(.system(size: 11)).foregroundStyle(Brand.secondary) }
                TableColumn("Область") { row in
                    Text(row.personal.first?.scopeTitle ?? "Все приложения").font(.system(size: 11))
                }
            }
            HStack {
                Button("Назад") { dictionary.previous(words: knowledge.words) }.disabled(dictionary.loading || dictionary.pageNumber == 1)
                Text("Страница \(dictionary.pageNumber) · до 200 слов").font(.system(size: 12)).foregroundStyle(Brand.secondary)
                Button("Далее") { dictionary.next(words: knowledge.words) }.disabled(dictionary.loading || !dictionary.page.hasNext)
                Spacer()
                Button("Удалить личную запись", role: .destructive) {
                    if let row = dictionary.page.rows.first(where: { $0.id == wordSelection }), let word = row.personal.first { knowledge.removeWord(word) }
                }.disabled(dictionary.page.rows.first(where: { $0.id == wordSelection })?.personal.isEmpty != false)
            }.font(.system(size: 12))
        }
        .onChange(of: dictionary.language) { _, _ in wordSelection = nil; dictionary.reload(words: knowledge.words) }
        .onChange(of: dictionary.source) { _, _ in wordSelection = nil; dictionary.reload(words: knowledge.words) }
        .onChange(of: dictionary.query) { _, _ in wordSelection = nil; dictionary.reload(words: knowledge.words, debounce: true) }
    }
}

private struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: UserRule
    let isNew: Bool
    let save: (UserRule) -> Void
    @State private var pattern: String
    @State private var replacement: String
    @State private var kind: RuleKind
    @State private var language: InputLanguage
    @State private var target: InputLanguage
    @State private var module: CorrectionModule?
    @State private var application: String
    init(rule: UserRule, isNew: Bool, save: @escaping (UserRule) -> Void) {
        original = rule; self.isNew = isNew; self.save = save
        _pattern = State(initialValue: rule.pattern); _replacement = State(initialValue: rule.replacement ?? "")
        _kind = State(initialValue: rule.kind); _language = State(initialValue: rule.language ?? .russian)
        _target = State(initialValue: rule.targetLanguage ?? (rule.language == .english ? .russian : .english))
        _module = State(initialValue: rule.module); _application = State(initialValue: rule.applicationBundleIdentifier ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "Новое личное правило" : "Изменить правило").font(.title2)
            TextField("Исходное слово", text: $pattern).textFieldStyle(.roundedBorder)
            Picker("Действие", selection: $kind) { Text("Не менять").tag(RuleKind.keep); Text("Всегда заменять").tag(RuleKind.convert) }
            if kind == .convert { TextField("Правильная замена", text: $replacement).textFieldStyle(.roundedBorder) }
            HStack {
                Picker("Язык исходного слова", selection: $language) { Text("Русский").tag(InputLanguage.russian); Text("English").tag(InputLanguage.english) }
                if kind == .convert { Picker("Язык замены", selection: $target) { Text("Русский").tag(InputLanguage.russian); Text("English").tag(InputLanguage.english) } }
            }
            Picker("Модуль", selection: $module) { Text("Оба").tag(CorrectionModule?.none); Text("Switcher").tag(CorrectionModule?.some(.switcher)); Text("Spell").tag(CorrectionModule?.some(.spell)) }
            TextField("Bundle ID приложения — пусто для всех", text: $application).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Сохранить") { submit() }.keyboardShortcut(.defaultAction)
                .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pattern.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: { $0.isWhitespace }) || (kind == .convert && replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
        }.padding(28).frame(width: 600).background(MetalBackground(tint: Brand.panel, textureOpacity: 0.12)).foregroundStyle(Brand.ink).tint(Brand.accent).preferredColorScheme(.light)
    }
    private func submit() {
        var value = original
        value = UserRule(id: original.id, kind: kind, pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines),
            replacement: kind == .convert ? replacement.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            language: language, applicationBundleIdentifier: application.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : application.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: original.createdAt, module: kind == .convert && language == target ? .spell : module,
            origin: .manual, enabled: original.enabled, targetLanguage: kind == .convert ? target : language, confirmations: original.confirmations)
        save(value); dismiss()
    }
}

private struct WordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State var language: InputLanguage
    let save: (String, InputLanguage) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Добавить личное слово").font(.title2)
            Picker("Язык", selection: $language) { Text("Русский").tag(InputLanguage.russian); Text("English").tag(InputLanguage.english) }.pickerStyle(.segmented)
            TextField("Имя, название или слово", text: $word).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Добавить") { save(word, language); dismiss() }
                .keyboardShortcut(.defaultAction).disabled(PersonalWordValidation.normalized(word, language: language) == nil) }
        }.padding(28).frame(width: 450).background(MetalBackground(tint: Brand.panel, textureOpacity: 0.12)).foregroundStyle(Brand.ink).tint(Brand.accent).preferredColorScheme(.light)
    }
}
