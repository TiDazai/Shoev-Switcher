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

    func addRule(
        kind: RuleKind,
        pattern: String,
        replacement: String? = nil,
        language: InputLanguage? = nil,
        applicationBundleIdentifier: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.insertRule(
                kind: kind,
                pattern: pattern,
                replacement: replacement,
                language: language,
                applicationBundleIdentifier: applicationBundleIdentifier
            )
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
    }

    private func flushPending() {
        flushScheduled = false
        guard !pendingEntries.isEmpty else { return }
        let entries = pendingEntries
        pendingEntries.removeAll(keepingCapacity: true)

        do {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            for entry in entries { try insertEntry(entry) }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
        }
    }

    private func insertEntry(_ entry: JournalEntry) throws {
        let sql = """
            INSERT INTO journal_entries
            (created_at, app_bundle, app_name, original, replacement, source_language, target_language, kind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
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
        try step(statement)
    }

    private func readRecentEntries(limit: Int) throws -> [JournalEntry] {
        let statement = try prepare("""
            SELECT id, created_at, app_bundle, app_name, original, replacement,
                   source_language, target_language, kind
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
                kind: kind
            ))
        }
        return entries
    }

    private func insertRule(
        kind: RuleKind,
        pattern: String,
        replacement: String?,
        language: InputLanguage?,
        applicationBundleIdentifier: String?
    ) throws {
        let statement = try prepare("""
            INSERT INTO user_rules (kind, pattern, replacement, language, app_bundle, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
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
        try step(statement)
    }

    private func readRules() throws -> [UserRule] {
        let statement = try prepare("""
            SELECT id, kind, pattern, replacement, language, app_bundle, created_at
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
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
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
