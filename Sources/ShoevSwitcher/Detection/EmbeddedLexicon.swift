import Foundation
import SQLite3

protocol LexiconScoring: AnyObject {
    func score(for word: String, language: InputLanguage) -> Double?
}

final class EmbeddedLexicon: LexiconScoring {
    static let shared = EmbeddedLexicon()

    private let lock = NSLock()
    private var database: OpaquePointer?
    private var query: OpaquePointer?

    private init() {
        guard let url = Bundle.module.url(forResource: "lexicon", withExtension: "sqlite3") else {
            return
        }

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &opened, flags, nil) == SQLITE_OK else {
            if let opened { sqlite3_close(opened) }
            return
        }
        database = opened
        sqlite3_exec(opened, "PRAGMA query_only=ON", nil, nil, nil)
        sqlite3_exec(opened, "PRAGMA cache_size=-2048", nil, nil, nil)
        sqlite3_exec(opened, "PRAGMA mmap_size=8388608", nil, nil, nil)

        let sql = "SELECT score FROM words WHERE language=?1 AND word=?2"
        guard sqlite3_prepare_v2(opened, sql, -1, &query, nil) == SQLITE_OK else {
            sqlite3_close(opened)
            database = nil
            return
        }
    }

    deinit {
        if let query { sqlite3_finalize(query) }
        if let database { sqlite3_close(database) }
    }

    func score(for word: String, language: InputLanguage) -> Double? {
        let normalized = word.lowercased(with: Locale(identifier: "en_US_POSIX"))
        lock.lock()
        defer { lock.unlock() }
        guard let query else { return nil }

        sqlite3_reset(query)
        sqlite3_clear_bindings(query)
        sqlite3_bind_text(query, 1, language.rawValue, -1, Self.transient)
        sqlite3_bind_text(query, 2, normalized, -1, Self.transient)
        guard sqlite3_step(query) == SQLITE_ROW else { return nil }
        return Double(sqlite3_column_int(query, 0)) / 100
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
