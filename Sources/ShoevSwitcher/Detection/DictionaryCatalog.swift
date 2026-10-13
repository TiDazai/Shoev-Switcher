import Foundation
import SQLite3

enum DictionarySourceFilter: String, CaseIterable {
    case all = "Все слова", builtin = "Встроенные", personal = "Личные"
}

struct DictionaryRow: Identifiable, Equatable {
    let word: String
    let language: InputLanguage
    let builtin: Bool
    let personal: [PersonalWord]
    var id: String { language.rawValue + ":" + word }
}

struct DictionaryPage {
    let rows: [DictionaryRow]
    let hasNext: Bool
    let builtinCount: Int
    let personalCount: Int
}

/// Keyset pagination uses the (language, word) primary key, never OFFSET over
/// millions of records. Only one small page is materialized on a utility queue.
final class DictionaryCatalog {
    private let queue = DispatchQueue(label: "com.shoev.switcher.dictionary", qos: .utility)
    private var database: OpaquePointer?
    private var counts: [InputLanguage: Int] = [:]

    init(url: URL? = Bundle.module.url(forResource: "lexicon", withExtension: "sqlite3")) {
        guard let url else { return }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }; database = nil; return
        }
        sqlite3_exec(database, "PRAGMA query_only=ON; PRAGMA cache_size=-1024;", nil, nil, nil)
    }
    deinit { if let database { sqlite3_close(database) } }

    func page(language: InputLanguage, prefix: String = "", after cursor: String? = nil,
              source: DictionarySourceFilter = .all, personal: [PersonalWord] = [], limit: Int = 200,
              completion: @escaping (DictionaryPage) -> Void) {
        queue.async { [self] in
            let page = readPage(language: language, prefix: prefix, cursor: cursor, source: source, personal: personal, limit: limit)
            DispatchQueue.main.async { completion(page) }
        }
    }

    private func readPage(language: InputLanguage, prefix: String, cursor: String?, source: DictionarySourceFilter,
                          personal: [PersonalWord], limit: Int) -> DictionaryPage {
        let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "en_US_POSIX")).precomposedStringWithCanonicalMapping
        let size = max(1, min(limit, 200))
        let custom = personal.filter { $0.language == language }
        let eligible = custom.filter { $0.word.hasPrefix(prefix) && (cursor == nil || Self.before(cursor!, $0.word)) }
        let grouped = Dictionary(grouping: eligible, by: \.word)
        var rows: [String: DictionaryRow] = [:]
        if source != .personal, let database {
            var statement: OpaquePointer?
            let sql = "SELECT word FROM words WHERE language=? AND word>=? AND word<? AND word>? ORDER BY word LIMIT ?;"
            if sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK {
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_int(statement, 1, language == .english ? 0 : 1)
                bind(prefix, statement, 2); bind(prefix + "\u{10FFFF}", statement, 3); bind(cursor ?? "", statement, 4)
                sqlite3_bind_int(statement, 5, Int32(size + 1))
                while sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) {
                    let word = String(cString: value)
                    rows[word] = DictionaryRow(word: word, language: language, builtin: true, personal: grouped[word] ?? [])
                }
            } else { sqlite3_finalize(statement) }
        }
        if source != .builtin {
            for (word, variants) in grouped.sorted(by: { Self.before($0.key, $1.key) }).prefix(size + 1) {
                rows[word] = DictionaryRow(word: word, language: language, builtin: rows[word]?.builtin ?? contains(word, language: language), personal: variants.sorted { a, b in
                    if (a.applicationBundleIdentifier == nil) != (b.applicationBundleIdentifier == nil) { return a.applicationBundleIdentifier == nil }
                    if (a.origin == .manual) != (b.origin == .manual) { return a.origin == .manual }
                    return a.createdAt > b.createdAt
                })
            }
        }
        let sorted = rows.values.sorted { Self.before($0.word, $1.word) }
        return DictionaryPage(rows: Array(sorted.prefix(size)), hasNext: sorted.count > size,
            builtinCount: count(language), personalCount: Set(custom.map(\.word)).count)
    }

    private func count(_ language: InputLanguage) -> Int {
        if let value = counts[language] { return value }
        guard let database else { return 0 }
        var query: OpaquePointer?
        let key = language == .english ? "english_words" : "russian_words"
        if sqlite3_prepare_v2(database, "SELECT value FROM metadata WHERE key=?", -1, &query, nil) == SQLITE_OK {
            bind(key, query, 1)
            if sqlite3_step(query) == SQLITE_ROW, let text = sqlite3_column_text(query, 0), let count = Int(String(cString: text)) {
                counts[language] = count; sqlite3_finalize(query); return count
            }
        }
        sqlite3_finalize(query)
        query = nil
        if sqlite3_prepare_v2(database, "SELECT count(*) FROM words WHERE language=?", -1, &query, nil) == SQLITE_OK {
            sqlite3_bind_int(query, 1, language == .english ? 0 : 1)
            if sqlite3_step(query) == SQLITE_ROW { counts[language] = Int(sqlite3_column_int64(query, 0)) }
        }
        sqlite3_finalize(query)
        return counts[language] ?? 0
    }

    private func contains(_ word: String, language: InputLanguage) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM words WHERE language=? AND word=?", -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement); return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, language == .english ? 0 : 1); bind(word, statement, 2)
        return sqlite3_step(statement) == SQLITE_ROW
    }
    private func bind(_ text: String, _ statement: OpaquePointer?, _ index: Int32) {
        sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    private static func before(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }
}
