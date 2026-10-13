import Foundation
import SQLite3

enum JournalStoreError: Error {
    case applicationSupportUnavailable
    case sqlite(String)
}

final class JournalStore {
    private let queue = DispatchQueue(label: "com.shoev.switcher.journal", qos: .utility)
    private let cipher: JournalCipher
    private var database: OpaquePointer?
    private var pendingEntries: [JournalEntry] = []
    private var flushScheduled = false

    init(baseDirectory: URL? = nil) throws {
        let directory: URL
        if let baseDirectory {
            directory = baseDirectory
        } else {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw JournalStoreError.applicationSupportUnavailable
            }
            directory = applicationSupport.appendingPathComponent("Shoev Switcher", isDirectory: true)
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        cipher = try JournalCipher(directory: directory)
        let databaseURL = directory.appendingPathComponent("journal.sqlite3")
        try openDatabase(at: databaseURL)
        try migrate()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func enqueue(_ entry: JournalEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingEntries.append(entry)
            if self.pendingEntries.count >= 25 {
                self.flushPending()
            } else if !self.flushScheduled {
                self.flushScheduled = true
                self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.flushPending()
                }
            }
        }
    }

    func recentEntries(limit: Int = 500, completion: @escaping ([JournalEntry]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.flushPending()
            let entries = (try? self.readRecentEntries(limit: limit)) ?? []
            DispatchQueue.main.async { completion(entries) }
        }
    }

    func loadRules() -> [UserRule] {
        queue.sync { (try? readRules()) ?? [] }
    }

    /// Drain queued writes before closing the app, including the final partial batch.
    func flush() { queue.sync { flushPending() } }

    func addRule(
        kind: RuleKind,
        pattern: String,
        replacement: String? = nil,
        language: InputLanguage? = nil,
        applicationBundleIdentifier: String? = nil,
        module: CorrectionModule? = nil,
        origin: PersonalOrigin = .manual,
        targetLanguage: InputLanguage? = nil,
        completion: (() -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            _ = try? self.insertRule(
                kind: kind,
                pattern: pattern,
                replacement: replacement,
                language: language,
                applicationBundleIdentifier: applicationBundleIdentifier,
                module: module, origin: origin, targetLanguage: targetLanguage
            )
            DispatchQueue.main.async { completion?() }
        }
    }

    func rules(completion: @escaping ([UserRule]) -> Void) {
        queue.async { [weak self] in
            let rules = (try? self?.readRules()) ?? []
            DispatchQueue.main.async { completion(rules) }
        }
    }

    func updateRule(_ rule: UserRule, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            try? self?.replaceRule(rule)
            DispatchQueue.main.async { completion?() }
        }
    }

    func deleteRule(id: Int64, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            try? self?.deleteRow(table: "user_rules", id: id)
            DispatchQueue.main.async { completion?() }
        }
    }

    func importRules(_ rules: [UserRule], completion: ((Int) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            var imported = 0
            for rule in rules where !rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard (try? self.containsEquivalentRule(rule)) == false else { continue }
                if (try? self.insertRule(
                    kind: rule.kind,
                    pattern: rule.pattern,
                    replacement: rule.replacement,
                    language: rule.language,
                    applicationBundleIdentifier: rule.applicationBundleIdentifier,
                    module: rule.module, origin: rule.origin ?? .manual,
                    targetLanguage: rule.targetLanguage, confirmations: rule.confirmations, enabled: rule.isEnabled
                )) != nil {
                    imported += 1
                }
            }
            DispatchQueue.main.async { completion?(imported) }
        }
    }

    func deleteJournalEntry(id: Int64, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.flushPending()
            try? self.deleteRow(table: "journal_entries", id: id)
            DispatchQueue.main.async { completion?() }
        }
    }

    /// Compatibility for historical callers only; live input uses verified
    /// AdaptiveLearningController receipts and the three-confirmation policy.
    @available(*, deprecated, message: "Use verified AdaptiveLearningController feedback and recordProof.")
    func recordManualConversion(
        original: String,
        replacement: String,
        sourceLanguage: InputLanguage,
        targetLanguage: InputLanguage,
        completion: ((Bool) -> Void)? = nil
    ) {
        queue.async { [weak self] in
            let learned = (try? self?.recordLearningObservation(
                original: original,
                replacement: replacement,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )) ?? false
            DispatchQueue.main.async { completion?(learned) }
        }
    }

    func learningEntries(completion: @escaping ([LearningEntry]) -> Void) {
        queue.async { [weak self] in
            let entries = (try? self?.readLearningEntries()) ?? []
            DispatchQueue.main.async { completion(entries) }
        }
    }

    func deleteLearningEntry(
        id: Int64,
        removeLearnedRule: Bool,
        completion: (() -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            if removeLearnedRule,
               let entry = try? self.readLearningEntries().first(where: { $0.id == id }),
               let ruleID = entry.learnedRuleID {
                try? self.deleteRow(table: "user_rules", id: ruleID)
            }
            try? self.deleteRow(table: "learning_stats", id: id)
            DispatchQueue.main.async { completion?() }
        }
    }

    func deleteAllJournalEntries(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingEntries.removeAll()
            try? self.execute("DELETE FROM journal_entries;")
            DispatchQueue.main.async { completion?() }
        }
    }

    private func openDatabase(at url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            throw JournalStoreError.sqlite(lastError)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func migrate() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS journal_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at REAL NOT NULL,
                app_bundle TEXT,
                app_name TEXT,
                original BLOB NOT NULL,
                replacement BLOB,
                source_language TEXT,
                target_language TEXT,
                kind TEXT NOT NULL
            );
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS user_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                pattern BLOB NOT NULL,
                replacement BLOB,
                language TEXT,
                app_bundle TEXT,
                created_at REAL NOT NULL
            );
            """)
        try execute("CREATE INDEX IF NOT EXISTS journal_created_at ON journal_entries(created_at DESC);")
        try execute("""
            CREATE TABLE IF NOT EXISTS learning_stats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                original BLOB NOT NULL,
                replacement BLOB NOT NULL,
                source_language TEXT NOT NULL,
                target_language TEXT NOT NULL,
                correction_count INTEGER NOT NULL,
                updated_at REAL NOT NULL,
                learned_rule_id INTEGER
            );
            """)
        if try !columnExists("learned_rule_id", table: "learning_stats") {
            try execute("ALTER TABLE learning_stats ADD COLUMN learned_rule_id INTEGER;")
        }
        try migrateKnowledge()
    }

    private func flushPending() {
        flushScheduled = false
        guard !pendingEntries.isEmpty else { return }
        let entries = pendingEntries

        do {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            for entry in entries { try insertEntry(entry) }
            try execute("COMMIT;")
            pendingEntries.removeFirst(entries.count)
        } catch {
            try? execute("ROLLBACK;")
        }
    }

    private func insertEntry(_ entry: JournalEntry) throws {
        let sql = """
            INSERT INTO journal_entries
            (created_at, app_bundle, app_name, original, replacement, source_language, target_language, kind, event_id, outcome)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, entry.createdAt.timeIntervalSince1970)
        bind(entry.applicationBundleIdentifier, to: statement, index: 2)
        bind(entry.applicationName, to: statement, index: 3)
        bind(try cipher.encrypt(entry.original), to: statement, index: 4)
        if let replacement = entry.replacement {
            bind(try cipher.encrypt(replacement), to: statement, index: 5)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        bind(entry.sourceLanguage?.rawValue, to: statement, index: 6)
        bind(entry.targetLanguage?.rawValue, to: statement, index: 7)
        bind(entry.kind.rawValue, to: statement, index: 8)
        bind(entry.eventID, to: statement, index: 9)
        bind(entry.outcome?.rawValue, to: statement, index: 10)
        try step(statement)
    }

    private func readRecentEntries(limit: Int) throws -> [JournalEntry] {
        let statement = try prepare("""
            SELECT id, created_at, app_bundle, app_name, original, replacement,
                   source_language, target_language, kind, event_id, outcome
            FROM journal_entries ORDER BY created_at DESC LIMIT ?;
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(1, min(limit, 5_000))))

        var entries: [JournalEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let originalData = blob(statement, column: 4),
                  let original = try? cipher.decrypt(originalData),
                  let kindText = text(statement, column: 8),
                  let kind = JournalEventKind(rawValue: kindText) else { continue }
            let replacement = blob(statement, column: 5).flatMap { try? cipher.decrypt($0) }
            entries.append(JournalEntry(
                id: sqlite3_column_int64(statement, 0),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                applicationBundleIdentifier: text(statement, column: 2),
                applicationName: text(statement, column: 3),
                original: original,
                replacement: replacement,
                sourceLanguage: text(statement, column: 6).flatMap(InputLanguage.init(rawValue:)),
                targetLanguage: text(statement, column: 7).flatMap(InputLanguage.init(rawValue:)),
                kind: kind, eventID: text(statement, column: 9),
                outcome: text(statement, column: 10).flatMap(FeedbackOutcome.init(rawValue:))
            ))
        }
        return entries
    }

    private func insertRule(
        kind: RuleKind,
        pattern: String,
        replacement: String?,
        language: InputLanguage?,
        applicationBundleIdentifier: String?,
        module: CorrectionModule? = nil,
        origin: PersonalOrigin = .manual,
        targetLanguage: InputLanguage? = nil,
        confirmations: Int? = nil,
        enabled: Bool = true
    ) throws -> Int64 {
        let statement = try prepare("""
            INSERT INTO user_rules (kind, pattern, replacement, language, app_bundle, created_at, module, origin, enabled, target_language, confirmations)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        bind(kind.rawValue, to: statement, index: 1)
        bind(try cipher.encrypt(pattern), to: statement, index: 2)
        if let replacement {
            bind(try cipher.encrypt(replacement), to: statement, index: 3)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        bind(language?.rawValue, to: statement, index: 4)
        bind(applicationBundleIdentifier, to: statement, index: 5)
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
        bind(module?.rawValue, to: statement, index: 7)
        bind(origin.rawValue, to: statement, index: 8)
        sqlite3_bind_int(statement, 9, enabled ? 1 : 0)
        bind(targetLanguage?.rawValue, to: statement, index: 10)
        if let confirmations { sqlite3_bind_int(statement, 11, Int32(confirmations)) } else { sqlite3_bind_null(statement, 11) }
        try step(statement)
        let id = sqlite3_last_insert_rowid(database)
        try syncWordForRule(UserRule(id: id, kind: kind, pattern: pattern, replacement: replacement,
            language: language, applicationBundleIdentifier: applicationBundleIdentifier, createdAt: Date(),
            module: module, origin: origin, enabled: enabled, targetLanguage: targetLanguage, confirmations: confirmations))
        return id
    }

    private func replaceRule(_ rule: UserRule) throws {
        let statement = try prepare("""
            UPDATE user_rules
            SET kind = ?, pattern = ?, replacement = ?, language = ?, app_bundle = ?, module = ?, origin = ?, enabled = ?, target_language = ?, confirmations = ?
            WHERE id = ?;
            """)
        defer { sqlite3_finalize(statement) }
        bind(rule.kind.rawValue, to: statement, index: 1)
        bind(try cipher.encrypt(rule.pattern), to: statement, index: 2)
        if let replacement = rule.replacement {
            bind(try cipher.encrypt(replacement), to: statement, index: 3)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        bind(rule.language?.rawValue, to: statement, index: 4)
        bind(rule.applicationBundleIdentifier, to: statement, index: 5)
        bind(rule.module?.rawValue, to: statement, index: 6)
        bind(rule.origin?.rawValue ?? PersonalOrigin.manual.rawValue, to: statement, index: 7)
        sqlite3_bind_int(statement, 8, rule.isEnabled ? 1 : 0)
        bind(rule.targetLanguage?.rawValue, to: statement, index: 9)
        if let count = rule.confirmations { sqlite3_bind_int(statement, 10, Int32(count)) } else { sqlite3_bind_null(statement, 10) }
        sqlite3_bind_int64(statement, 11, rule.id)
        try step(statement)
        let cleanup = try prepare("DELETE FROM personal_words WHERE rule_id=?;")
        defer { sqlite3_finalize(cleanup) }
        sqlite3_bind_int64(cleanup, 1, rule.id)
        try step(cleanup)
        if rule.isEnabled { try syncWordForRule(rule) }
    }

    private func deleteRow(table: String, id: Int64) throws {
        guard table == "user_rules" || table == "journal_entries" || table == "learning_stats" else {
            return
        }
        let statement = try prepare("DELETE FROM \(table) WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try step(statement)
        if table == "user_rules" {
            let observations = try prepare("DELETE FROM adaptive_observations WHERE rule_id=?;")
            defer { sqlite3_finalize(observations) }
            sqlite3_bind_int64(observations, 1, id); try step(observations)
            let linked = try prepare("DELETE FROM personal_words WHERE rule_id=?;")
            defer { sqlite3_finalize(linked) }
            sqlite3_bind_int64(linked, 1, id)
            try step(linked)
        }
    }

    private func equivalentRule(_ candidate: UserRule) throws -> UserRule? {
        try readRules().first { rule in
            rule.kind == candidate.kind
                && normalize(rule.pattern) == normalize(candidate.pattern)
                && rule.replacement.map(normalize) == candidate.replacement.map(normalize)
                && rule.language == candidate.language
                && rule.applicationBundleIdentifier == candidate.applicationBundleIdentifier
                && rule.module == candidate.module
        }
    }

    private func containsEquivalentRule(_ candidate: UserRule) throws -> Bool {
        try equivalentRule(candidate) != nil
    }

    private func recordLearningObservation(
        original: String,
        replacement: String,
        sourceLanguage: InputLanguage,
        targetLanguage: InputLanguage
    ) throws -> Bool {
        let candidate = UserRule(
            id: 0,
            kind: .convert,
            pattern: original,
            replacement: replacement,
            language: sourceLanguage,
            applicationBundleIdentifier: nil,
            createdAt: Date()
        )
        let existingRule = try equivalentRule(candidate)

        let statement = try prepare("""
            SELECT id, original, replacement, source_language, target_language,
                   correction_count, learned_rule_id
            FROM learning_stats;
            """)
        defer { sqlite3_finalize(statement) }

        var matchingID: Int64?
        var count = 0
        var learnedRuleID: Int64?
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let originalData = blob(statement, column: 1),
                  let replacementData = blob(statement, column: 2),
                  let storedOriginal = try? cipher.decrypt(originalData),
                  let storedReplacement = try? cipher.decrypt(replacementData),
                  text(statement, column: 3) == sourceLanguage.rawValue,
                  text(statement, column: 4) == targetLanguage.rawValue,
                  normalize(storedOriginal) == normalize(original),
                  normalize(storedReplacement) == normalize(replacement) else { continue }
            matchingID = sqlite3_column_int64(statement, 0)
            count = Int(sqlite3_column_int(statement, 5))
            if sqlite3_column_type(statement, 6) != SQLITE_NULL {
                learnedRuleID = sqlite3_column_int64(statement, 6)
            }
            break
        }

        let nextCount = count + 1
        var learnedNow = false
        if nextCount >= 2, learnedRuleID == nil {
            if let existingRule {
                learnedRuleID = existingRule.id
            } else {
                learnedRuleID = try insertRule(
                kind: .convert,
                pattern: original,
                replacement: replacement,
                language: sourceLanguage,
                applicationBundleIdentifier: nil
            )
                learnedNow = true
            }
        }

        if let matchingID {
            let update = try prepare("""
                UPDATE learning_stats
                SET correction_count = ?, updated_at = ?, learned_rule_id = ?
                WHERE id = ?;
                """)
            defer { sqlite3_finalize(update) }
            sqlite3_bind_int(update, 1, Int32(nextCount))
            sqlite3_bind_double(update, 2, Date().timeIntervalSince1970)
            if let learnedRuleID {
                sqlite3_bind_int64(update, 3, learnedRuleID)
            } else {
                sqlite3_bind_null(update, 3)
            }
            sqlite3_bind_int64(update, 4, matchingID)
            try step(update)
        } else {
            let insert = try prepare("""
                INSERT INTO learning_stats
                (original, replacement, source_language, target_language,
                 correction_count, updated_at, learned_rule_id)
                VALUES (?, ?, ?, ?, 1, ?, ?);
                """)
            defer { sqlite3_finalize(insert) }
            bind(try cipher.encrypt(original), to: insert, index: 1)
            bind(try cipher.encrypt(replacement), to: insert, index: 2)
            bind(sourceLanguage.rawValue, to: insert, index: 3)
            bind(targetLanguage.rawValue, to: insert, index: 4)
            sqlite3_bind_double(insert, 5, Date().timeIntervalSince1970)
            if let learnedRuleID {
                sqlite3_bind_int64(insert, 6, learnedRuleID)
            } else {
                sqlite3_bind_null(insert, 6)
            }
            try step(insert)
        }
        return learnedNow
    }

    private func readLearningEntries() throws -> [LearningEntry] {
        let statement = try prepare("""
            SELECT id, original, replacement, source_language, target_language,
                   correction_count, updated_at, learned_rule_id
            FROM learning_stats ORDER BY updated_at DESC;
            """)
        defer { sqlite3_finalize(statement) }
        var result: [LearningEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let originalData = blob(statement, column: 1),
                  let replacementData = blob(statement, column: 2),
                  let original = try? cipher.decrypt(originalData),
                  let replacement = try? cipher.decrypt(replacementData),
                  let sourceText = text(statement, column: 3),
                  let source = InputLanguage(rawValue: sourceText),
                  let targetText = text(statement, column: 4),
                  let target = InputLanguage(rawValue: targetText) else { continue }
            let ruleID = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 7)
            result.append(LearningEntry(
                id: sqlite3_column_int64(statement, 0),
                original: original,
                replacement: replacement,
                sourceLanguage: source,
                targetLanguage: target,
                correctionCount: Int(sqlite3_column_int(statement, 5)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                learnedRuleID: ruleID
            ))
        }
        return result
    }

    private func columnExists(_ column: String, table: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if text(statement, column: 1) == column { return true }
        }
        return false
    }

    private func normalize(_ value: String) -> String {
        value.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func readRules() throws -> [UserRule] {
        let statement = try prepare("""
            SELECT id, kind, pattern, replacement, language, app_bundle, created_at, module, origin, enabled, target_language, confirmations
            FROM user_rules ORDER BY created_at DESC;
            """)
        defer { sqlite3_finalize(statement) }
        var result: [UserRule] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kindText = text(statement, column: 1),
                  let kind = RuleKind(rawValue: kindText),
                  let patternData = blob(statement, column: 2),
                  let pattern = try? cipher.decrypt(patternData) else { continue }
            let replacement = blob(statement, column: 3).flatMap { try? cipher.decrypt($0) }
            result.append(UserRule(
                id: sqlite3_column_int64(statement, 0),
                kind: kind,
                pattern: pattern,
                replacement: replacement,
                language: text(statement, column: 4).flatMap(InputLanguage.init(rawValue:)),
                applicationBundleIdentifier: text(statement, column: 5),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                module: text(statement, column: 7).flatMap(CorrectionModule.init(rawValue:)),
                origin: text(statement, column: 8).flatMap(PersonalOrigin.init(rawValue:)),
                enabled: sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : sqlite3_column_int(statement, 9) != 0,
                targetLanguage: text(statement, column: 10).flatMap(InputLanguage.init(rawValue:)),
                confirmations: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 11))
            ))
        }
        return result
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw JournalStoreError.sqlite(lastError)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw JournalStoreError.sqlite(lastError)
        }
        return statement
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw JournalStoreError.sqlite(lastError)
        }
    }

    private func bind(_ value: String?, to statement: OpaquePointer, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bind(_ value: Data, to statement: OpaquePointer, index: Int32) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private func blob(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private var lastError: String {
        database.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "Unknown SQLite error"
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension JournalStore {
    private func migrateKnowledge() throws {
        for (column, type) in [("module", "TEXT"), ("origin", "TEXT"), ("enabled", "INTEGER"),
                               ("target_language", "TEXT"), ("confirmations", "INTEGER")] {
            if try !columnExists(column, table: "user_rules") { try execute("ALTER TABLE user_rules ADD COLUMN \(column) \(type);") }
        }
        for column in ["event_id", "outcome"] {
            if try !columnExists(column, table: "journal_entries") { try execute("ALTER TABLE journal_entries ADD COLUMN \(column) TEXT;") }
        }
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS journal_event_id ON journal_entries(event_id);")
        try execute("UPDATE journal_entries SET outcome='unverified' WHERE outcome='pending';")
        try execute("""
            CREATE TABLE IF NOT EXISTS personal_words (
                word_key TEXT PRIMARY KEY, word BLOB NOT NULL, language TEXT NOT NULL,
                origin TEXT NOT NULL, app_bundle TEXT, rule_id INTEGER, created_at REAL NOT NULL, module TEXT
            );
            CREATE TABLE IF NOT EXISTS adaptive_observations (
                observation_key TEXT PRIMARY KEY, pattern BLOB NOT NULL, replacement BLOB,
                source_language TEXT NOT NULL, target_language TEXT NOT NULL, module TEXT NOT NULL,
                kind TEXT NOT NULL, app_bundle TEXT, confirmations INTEGER NOT NULL,
                first_at REAL NOT NULL, last_at REAL NOT NULL, rule_id INTEGER
            );
            CREATE TABLE IF NOT EXISTS adaptive_receipts (id TEXT PRIMARY KEY, created_at REAL NOT NULL);
            """)
        if try !columnExists("module", table: "personal_words") { try execute("ALTER TABLE personal_words ADD COLUMN module TEXT;") }
        try execute("UPDATE user_rules SET origin='learning' WHERE origin IS NULL AND id IN (SELECT learned_rule_id FROM learning_stats);")
        // Once-only import of existing personal rules; never reads a typed diary
        // or turns historical journal messages into dictionary words.
        let marker = "personal_words_migrated_v1"
        try execute("CREATE TABLE IF NOT EXISTS knowledge_metadata (key TEXT PRIMARY KEY, value TEXT);")
        let legacyReview = try prepare("SELECT value FROM knowledge_metadata WHERE key='legacy_learning_reviewed_v1';")
        defer { sqlite3_finalize(legacyReview) }
        if sqlite3_step(legacyReview) != SQLITE_ROW {
            // Old learning counted immediate toggles, not verified acceptance.
            // Preserve these rows, but don't silently trust their global effects.
            try execute("""
                UPDATE user_rules SET enabled=0, confirmations=(SELECT correction_count FROM learning_stats WHERE learned_rule_id=user_rules.id LIMIT 1)
                WHERE origin='learning' AND module IS NULL AND enabled IS NULL;
                DELETE FROM personal_words WHERE origin!='manual' AND rule_id IN
                    (SELECT id FROM user_rules WHERE origin='learning' AND enabled=0);
                INSERT INTO knowledge_metadata VALUES ('legacy_learning_reviewed_v1','1');
                """)
        }
        let check = try prepare("SELECT value FROM knowledge_metadata WHERE key=?;")
        defer { sqlite3_finalize(check) }
        bind(marker, to: check, index: 1)
        if sqlite3_step(check) != SQLITE_ROW {
            for rule in try readRules() where rule.isEnabled { try syncWordForRule(rule) }
            try execute("INSERT INTO knowledge_metadata VALUES ('personal_words_migrated_v1','1');")
        }
    }

    func resolveOutcome(eventID: String, outcome: FeedbackOutcome) {
        queue.async { [weak self] in
            guard let self else { return }
            if let index = self.pendingEntries.firstIndex(where: { $0.eventID == eventID }) {
                self.pendingEntries[index].outcome = outcome
            } else if let statement = try? self.prepare("UPDATE journal_entries SET outcome=? WHERE event_id=?;") {
                defer { sqlite3_finalize(statement) }
                self.bind(outcome.rawValue, to: statement, index: 1)
                self.bind(eventID, to: statement, index: 2)
                try? self.step(statement)
            }
        }
    }

    func personalWords(completion: @escaping ([PersonalWord]) -> Void) {
        queue.async { [weak self] in
            let words = (try? self?.readPersonalWords()) ?? []
            DispatchQueue.main.async { completion(words) }
        }
    }
    func loadPersonalWords() -> [PersonalWord] { queue.sync { (try? readPersonalWords()) ?? [] } }

    func addPersonalWord(_ word: String, language: InputLanguage, origin: PersonalOrigin = .manual,
                         completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            let saved = (try? self?.upsertWord(word, language: language, origin: origin, app: nil, ruleID: nil)) ?? false
            DispatchQueue.main.async { completion(saved) }
        }
    }

    func deletePersonalWord(id: String, completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if let word = try? self.readPersonalWords().first(where: { $0.id == id }), let ruleID = word.ruleID,
               let rule = try? self.readRules().first(where: { $0.id == ruleID }), rule.kind == .accept {
                try? self.deleteRow(table: "user_rules", id: ruleID)
            }
            if let statement = try? self.prepare("DELETE FROM personal_words WHERE word_key=?;") {
                defer { sqlite3_finalize(statement) }; self.bind(id, to: statement, index: 1); try? self.step(statement)
            }
            DispatchQueue.main.async { completion() }
        }
    }

    private func readPersonalWords() throws -> [PersonalWord] {
        let statement = try prepare("SELECT word_key,word,language,origin,app_bundle,rule_id,created_at,module FROM personal_words ORDER BY created_at DESC;")
        defer { sqlite3_finalize(statement) }
        var result: [PersonalWord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, column: 0), let encrypted = blob(statement, column: 1),
                  let word = try? cipher.decrypt(encrypted), let rawLanguage = text(statement, column: 2),
                  let language = InputLanguage(rawValue: rawLanguage), let source = text(statement, column: 3),
                  let origin = PersonalOrigin(rawValue: source) else { continue }
            result.append(PersonalWord(id: id, word: word, language: language, origin: origin,
                applicationBundleIdentifier: text(statement, column: 4),
                ruleID: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 5),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)), module: text(statement, column: 7).flatMap(CorrectionModule.init(rawValue:))))
        }
        return result
    }

    @discardableResult
    private func upsertWord(_ raw: String, language: InputLanguage, origin: PersonalOrigin,
                            app: String?, ruleID: Int64?, module: CorrectionModule? = nil) throws -> Bool {
        guard let word = PersonalWordValidation.normalized(raw, language: language) else { return false }
        let key = cipher.fingerprint("word|\(language.rawValue)|\(app ?? "*")|\(module?.rawValue ?? "*")|\(word)")
        let statement = try prepare("""
            INSERT INTO personal_words (word_key,word,language,origin,app_bundle,rule_id,created_at,module) VALUES (?,?,?,?,?,?,?,?)
            ON CONFLICT(word_key) DO UPDATE SET word=excluded.word,
                origin=CASE WHEN personal_words.origin='manual' THEN 'manual' ELSE excluded.origin END,
                rule_id=CASE WHEN excluded.origin='manual' THEN NULL WHEN personal_words.origin='manual' THEN personal_words.rule_id ELSE COALESCE(excluded.rule_id,personal_words.rule_id) END;
            """)
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, index: 1); bind(try cipher.encrypt(word), to: statement, index: 2)
        bind(language.rawValue, to: statement, index: 3); bind(origin.rawValue, to: statement, index: 4)
        bind(app, to: statement, index: 5)
        if let ruleID { sqlite3_bind_int64(statement, 6, ruleID) } else { sqlite3_bind_null(statement, 6) }
        sqlite3_bind_double(statement, 7, Date().timeIntervalSince1970); bind(module?.rawValue, to: statement, index: 8); try step(statement)
        return true
    }

    private func syncWordForRule(_ rule: UserRule) throws {
        guard rule.isEnabled else { return }
        let raw = rule.kind == .convert ? rule.replacement : rule.pattern
        guard let raw else { return }
        let inferred: InputLanguage? = PersonalWordValidation.normalized(raw, language: .english) != nil ? .english
            : (PersonalWordValidation.normalized(raw, language: .russian) != nil ? .russian : nil)
        let language = rule.kind == .convert ? (rule.targetLanguage ?? rule.language.map { rule.module == .spell ? $0 : ($0 == .english ? .russian : .english) } ?? inferred)
            : (rule.language ?? inferred)
        guard let language else { return }
        _ = try upsertWord(raw, language: language, origin: rule.origin == .learning ? .learning : .diary,
            app: rule.applicationBundleIdentifier, ruleID: rule.id, module: rule.kind == .keep ? rule.module : nil)
    }

    /// Only verified *user-directed* evidence is submitted here. Automatic
    /// corrections are never used as their own proof of correctness.
    func recordProof(_ proof: LearningProof, completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var learned = false
            do {
                try self.execute("BEGIN IMMEDIATE;")
                learned = try self.insertProof(proof)
                try self.execute("COMMIT;")
            } catch { try? self.execute("ROLLBACK;") }
            DispatchQueue.main.async { completion(learned) }
        }
    }

    private func insertProof(_ proof: LearningProof) throws -> Bool {
        let pattern = proof.pattern.lowercased(with: Locale(identifier: "en_US_POSIX")).precomposedStringWithCanonicalMapping
        guard !pattern.isEmpty, pattern.count <= 64,
              !pattern.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let word = proof.kind == .keep ? PersonalWordValidation.normalized(pattern, language: proof.sourceLanguage)
                : proof.replacement.flatMap({ PersonalWordValidation.normalized($0, language: proof.targetLanguage) }),
              !word.isEmpty else { return false }
        let receipt = try prepare("INSERT OR IGNORE INTO adaptive_receipts VALUES (?,?);")
        defer { sqlite3_finalize(receipt) }
        bind(proof.id, to: receipt, index: 1); sqlite3_bind_double(receipt, 2, proof.confirmedAt.timeIntervalSince1970)
        try step(receipt)
        guard sqlite3_changes(database) == 1 else { return false }
        let key = cipher.fingerprint("proof|\(proof.module.rawValue)|\(proof.kind.rawValue)|\(proof.sourceLanguage.rawValue)|\(proof.targetLanguage.rawValue)|\(proof.applicationBundleIdentifier ?? "*")|\(pattern)|\(word)")
        let select = try prepare("SELECT confirmations,first_at,last_at,rule_id FROM adaptive_observations WHERE observation_key=?;")
        defer { sqlite3_finalize(select) }; bind(key, to: select, index: 1)
        var count = 0; var first = proof.confirmedAt.timeIntervalSince1970; var last = -Double.infinity; var ruleID: Int64?
        if sqlite3_step(select) == SQLITE_ROW {
            count = Int(sqlite3_column_int(select, 0)); first = sqlite3_column_double(select, 1); last = sqlite3_column_double(select, 2)
            if sqlite3_column_type(select, 3) != SQLITE_NULL { ruleID = sqlite3_column_int64(select, 3) }
        }
        let now = proof.confirmedAt.timeIntervalSince1970
        // Duplicate key events and quick toggles are not independent evidence.
        guard now - last >= 5 else { return false }
        if now - last > 14 * 86_400, ruleID == nil { count = 0; first = now }
        count += 1
        var promoted = false
        if count >= 3, now - first >= 10, ruleID == nil {
            let existing = try readRules().first { $0.isEnabled && $0.origin != .learning && ($0.module == nil || $0.module == proof.module)
                && ($0.language == nil || $0.language == proof.sourceLanguage)
                && ($0.applicationBundleIdentifier == nil || $0.applicationBundleIdentifier == proof.applicationBundleIdentifier)
                && normalize($0.pattern) == normalize(pattern) }
            if existing == nil {
                ruleID = try insertRule(kind: proof.kind, pattern: pattern,
                    replacement: proof.kind == .keep ? nil : word, language: proof.sourceLanguage,
                    applicationBundleIdentifier: proof.applicationBundleIdentifier, module: proof.module,
                    origin: .learning, targetLanguage: proof.targetLanguage, confirmations: count)
                promoted = true
            }
        }
        let statement = try prepare("""
            INSERT INTO adaptive_observations VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(observation_key) DO UPDATE SET confirmations=excluded.confirmations,first_at=excluded.first_at,last_at=excluded.last_at,rule_id=excluded.rule_id;
            """)
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, index: 1); bind(try cipher.encrypt(pattern), to: statement, index: 2)
        if proof.kind != .keep { bind(try cipher.encrypt(word), to: statement, index: 3) } else { sqlite3_bind_null(statement, 3) }
        bind(proof.sourceLanguage.rawValue, to: statement, index: 4); bind(proof.targetLanguage.rawValue, to: statement, index: 5)
        bind(proof.module.rawValue, to: statement, index: 6); bind(proof.kind.rawValue, to: statement, index: 7)
        bind(proof.applicationBundleIdentifier, to: statement, index: 8); sqlite3_bind_int(statement, 9, Int32(count))
        sqlite3_bind_double(statement, 10, first); sqlite3_bind_double(statement, 11, now)
        if let ruleID { sqlite3_bind_int64(statement, 12, ruleID) } else { sqlite3_bind_null(statement, 12) }
        try step(statement)
        try execute("DELETE FROM adaptive_receipts WHERE created_at < \(now - 30 * 86_400);")
        return promoted
    }

    func observations(completion: @escaping ([AdaptiveObservation]) -> Void) {
        queue.async { [weak self] in
            let rows = (try? self?.readObservations()) ?? []
            DispatchQueue.main.async { completion(rows) }
        }
    }
    private func readObservations() throws -> [AdaptiveObservation] {
        let statement = try prepare("SELECT observation_key,pattern,replacement,source_language,target_language,module,kind,app_bundle,confirmations,last_at,rule_id FROM adaptive_observations ORDER BY last_at DESC LIMIT 1000;")
        defer { sqlite3_finalize(statement) }
        var rows: [AdaptiveObservation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, column: 0), let data = blob(statement, column: 1), let pattern = try? cipher.decrypt(data),
                  let source = text(statement, column: 3).flatMap(InputLanguage.init(rawValue:)),
                  let target = text(statement, column: 4).flatMap(InputLanguage.init(rawValue:)),
                  let module = text(statement, column: 5).flatMap(CorrectionModule.init(rawValue:)),
                  let kind = text(statement, column: 6).flatMap(RuleKind.init(rawValue:)) else { continue }
            rows.append(AdaptiveObservation(id: id, pattern: pattern,
                replacement: blob(statement, column: 2).flatMap { try? cipher.decrypt($0) }, sourceLanguage: source, targetLanguage: target,
                module: module, kind: kind, applicationBundleIdentifier: text(statement, column: 7),
                confirmations: Int(sqlite3_column_int(statement, 8)), lastConfirmedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
                learnedRuleID: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 10)))
        }
        return rows
    }

    func importPersonalWords(_ words: [PersonalWord], completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.execute("BEGIN IMMEDIATE;")
                for word in words {
                    _ = try self.upsertWord(word.word, language: word.language, origin: word.origin,
                        app: word.applicationBundleIdentifier, ruleID: nil, module: word.module)
                }
                try self.execute("COMMIT;")
            } catch { try? self.execute("ROLLBACK;") }
            DispatchQueue.main.async { completion() }
        }
    }

    func suspendLearnedRules(pattern: String, language: InputLanguage, module: CorrectionModule, app: String?, completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            for var rule in (try? self.readRules()) ?? [] where rule.origin == .learning && (rule.module == nil || rule.module == module)
                && rule.language == language && self.normalize(rule.pattern) == self.normalize(pattern)
                && (rule.applicationBundleIdentifier == nil || rule.applicationBundleIdentifier == app) {
                rule.enabled = false; try? self.replaceRule(rule)
            }
            DispatchQueue.main.async { completion() }
        }
    }
}
