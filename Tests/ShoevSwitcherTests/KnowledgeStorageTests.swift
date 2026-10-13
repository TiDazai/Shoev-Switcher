import AppKit
import SQLite3
import XCTest
@testable import ShoevSwitcher

final class KnowledgeStorageTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShoevKnowledge-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testThreeIndependentProofsPromoteAScopedRuleAndMarkedWord() throws {
        let store = try JournalStore(baseDirectory: directory)
        record(store, time: 0); record(store, time: 6)
        XCTAssertTrue(store.loadRules().isEmpty)
        record(store, time: 12)
        let rule = try XCTUnwrap(store.loadRules().first)
        XCTAssertEqual(rule.origin, .learning); XCTAssertEqual(rule.module, .switcher)
        XCTAssertEqual(rule.applicationBundleIdentifier, "com.example.Editor")
        XCTAssertEqual(rule.confirmations, 3)
        let word = try XCTUnwrap(store.loadPersonalWords().first)
        XCTAssertEqual(word.word, "привет"); XCTAssertEqual(word.origin, .learning)
        XCTAssertEqual(word.applicationBundleIdentifier, "com.example.Editor")
    }

    func testLegacyUnverifiedLearningIsPausedWithoutDeletingRulesOrManualWords() throws {
        let store = try JournalStore(baseDirectory: directory)
        let automatic = expectation(description: "old inferred rule")
        store.addRule(kind: .convert, pattern: "ghbdtn", replacement: "привет", language: .english,
            origin: .learning, targetLanguage: .russian) { automatic.fulfill() }
        wait(for: [automatic], timeout: 3)
        let manual = expectation(description: "manual rule is preserved")
        store.addRule(kind: .keep, pattern: "Timur", language: .english) { manual.fulfill() }
        wait(for: [manual], timeout: 3); store.flush()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("journal.sqlite3").path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "UPDATE user_rules SET enabled=NULL WHERE origin='learning'; DELETE FROM knowledge_metadata WHERE key='legacy_learning_reviewed_v1';", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let migrated = try JournalStore(baseDirectory: directory)
        XCTAssertEqual(migrated.loadRules().count, 2)
        XCTAssertEqual(migrated.loadRules().first(where: { $0.origin == .learning })?.isEnabled, false)
        XCTAssertEqual(migrated.loadRules().first(where: { $0.origin == .manual })?.isEnabled, true)
        XCTAssertEqual(migrated.loadPersonalWords().map(\.word), ["timur"])
    }
    func testDuplicatesAndQuickTogglesAreNotIndependentProofs() throws {
        let store = try JournalStore(baseDirectory: directory)
        record(store, time: 0, id: "same"); record(store, time: 6, id: "same")
        record(store, time: 1); record(store, time: 7)
        XCTAssertTrue(store.loadRules().isEmpty)
        let loaded = expectation(description: "evidence")
        store.observations { rows in XCTAssertEqual(rows.first?.confirmations, 2); loaded.fulfill() }
        wait(for: [loaded], timeout: 3)
    }
    func testJournalOutcomeCanBeResolvedBeforeAndAfterFlush() throws {
        let store = try JournalStore(baseDirectory: directory)
        store.enqueue(JournalEntry(id: 0, createdAt: Date(), applicationBundleIdentifier: nil, applicationName: nil,
            original: "ghbdtn", replacement: "привет", sourceLanguage: .english, targetLanguage: .russian,
            kind: .correction, eventID: "event", outcome: .pending))
        store.resolveOutcome(eventID: "event", outcome: .edited); store.flush()
        store.resolveOutcome(eventID: "event", outcome: .rejected)
        let loaded = expectation(description: "one audit event")
        store.recentEntries { rows in XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.outcome, .rejected); loaded.fulfill() }
        wait(for: [loaded], timeout: 3)
    }
    func testDiaryAndPersonalWordRoundTripAndRemoval() throws {
        let store = try JournalStore(baseDirectory: directory)
        let saved = expectation(description: "diary rule")
        store.addRule(kind: .convert, pattern: "helo", replacement: "hello", language: .english,
            module: .spell, targetLanguage: .english) { saved.fulfill() }
        wait(for: [saved], timeout: 3)
        let word = try XCTUnwrap(store.loadPersonalWords().first)
        XCTAssertEqual(word.word, "hello"); XCTAssertEqual(word.origin, .diary)
        let removed = expectation(description: "delete diary rule")
        store.deleteRule(id: try XCTUnwrap(store.loadRules().first?.id)) { removed.fulfill() }
        wait(for: [removed], timeout: 3)
        XCTAssertTrue(store.loadPersonalWords().isEmpty)
    }
    func testExplicitWordsAreDeduplicatedAndProtectedInBothModules() throws {
        let store = try JournalStore(baseDirectory: directory)
        for word in ["Shoev", "SHOEV"] {
            let saved = expectation(description: "personal word")
            store.addPersonalWord(word, language: .english) { result in XCTAssertTrue(result); saved.fulfill() }
            wait(for: [saved], timeout: 3)
        }
        XCTAssertEqual(store.loadPersonalWords().count, 1)
        let rules = RuleStore(); rules.replaceWords(store.loadPersonalWords())
        XCTAssertEqual(rules.decision(original: "shoev", alternative: "ырщу", sourceLanguage: .english, applicationBundleIdentifier: nil), .keep)
        XCTAssertEqual(rules.spellingDecision("shoev", language: .english, application: nil), .keep)
    }
    func testUntrustedURLsAndMixedLanguageWordsAreRejected() throws {
        let store = try JournalStore(baseDirectory: directory)
        for word in ["https://example.com", "hello мир", "alice@example.com", "password123", ""] {
            let saved = expectation(description: "invalid word")
            store.addPersonalWord(word, language: .english) { result in XCTAssertFalse(result); saved.fulfill() }
            wait(for: [saved], timeout: 3)
        }
        XCTAssertTrue(store.loadPersonalWords().isEmpty)
    }
    func testUserKnowledgeStaysEncryptedAtRest() throws {
        let store = try JournalStore(baseDirectory: directory)
        let saved = expectation(description: "encrypted word")
        store.addPersonalWord("privatesecretcanary", language: .english) { _ in saved.fulfill() }
        wait(for: [saved], timeout: 3); store.flush()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "sqlite3" || url.lastPathComponent.hasSuffix("-wal") {
            XCTAssertNil(try Data(contentsOf: url).range(of: Data("privatesecretcanary".utf8)))
        }
    }
    func testManualRulesOverrideLearningAndSuspensionDoesNotTouchManualRules() throws {
        let store = try JournalStore(baseDirectory: directory)
        record(store, time: 0); record(store, time: 6); record(store, time: 12)
        let manual = expectation(description: "manual authority")
        store.addRule(kind: .keep, pattern: "ghbdtn", language: .english, applicationBundleIdentifier: "com.example.Editor", module: .switcher) { manual.fulfill() }
        wait(for: [manual], timeout: 3)
        let paused = expectation(description: "suspend learned rule")
        store.suspendLearnedRules(pattern: "ghbdtn", language: .english, module: .switcher, app: "com.example.Editor") { paused.fulfill() }
        wait(for: [paused], timeout: 3)
        let rows = store.loadRules()
        XCTAssertEqual(rows.first(where: { $0.origin == .learning })?.isEnabled, false)
        XCTAssertEqual(rows.first(where: { $0.origin == .manual })?.isEnabled, true)
        let rules = RuleStore(); rules.replaceRules(rows)
        XCTAssertEqual(rules.decision(original: "ghbdtn", alternative: "привет", sourceLanguage: .english,
            applicationBundleIdentifier: "com.example.Editor"), .keep)
    }
    func testSpellingRulesCannotSwitchLayoutsAndPersonalScopeIsRespected() throws {
        let rules = RuleStore()
        rules.replaceRules([UserRule(id: 1, kind: .convert, pattern: "helo", replacement: "hello", language: .english,
            applicationBundleIdentifier: "com.example.Editor", createdAt: Date(), module: .spell, origin: .manual, targetLanguage: .english)])
        XCTAssertNil(rules.decision(original: "helo", alternative: "рудщ", sourceLanguage: .english, applicationBundleIdentifier: "com.example.Editor"))
        XCTAssertEqual(rules.spellingDecision("helo", language: .english, application: "com.example.Editor"),
            .convert(ConversionCandidate(original: "helo", replacement: "hello", sourceLanguage: .english, targetLanguage: .english)))
        XCTAssertNil(rules.spellingDecision("helo", language: .english, application: "com.other.Editor"))
    }

    func testSpellingOnlyKeepRuleDoesNotLeakThroughPersonalDictionary() throws {
        let store = try JournalStore(baseDirectory: directory)
        let saved = expectation(description: "scoped keep")
        store.addRule(kind: .keep, pattern: "helo", language: .english, module: .spell) { saved.fulfill() }
        wait(for: [saved], timeout: 3)
        let rules = RuleStore(); rules.replaceRules(store.loadRules()); rules.replaceWords(store.loadPersonalWords())
        XCTAssertEqual(store.loadPersonalWords().first?.module, .spell)
        XCTAssertNil(rules.decision(original: "helo", alternative: "рудщ", sourceLanguage: .english, applicationBundleIdentifier: nil))
        XCTAssertEqual(rules.spellingDecision("helo", language: .english, application: nil), .keep)
    }

    func testImportPreservesDisabledRuleAndWordLink() throws {
        let store = try JournalStore(baseDirectory: directory)
        let disabled = UserRule(id: 10, kind: .keep, pattern: "disabledtoken", replacement: nil, language: .english,
            applicationBundleIdentifier: nil, createdAt: Date(), module: .spell, origin: .manual, enabled: false)
        let imported = expectation(description: "disabled rule import")
        store.importRules([disabled]) { _ in imported.fulfill() }
        wait(for: [imported], timeout: 3)
        XCTAssertEqual(store.loadRules().first?.isEnabled, false)
        XCTAssertTrue(store.loadPersonalWords().isEmpty)
        let saved = expectation(description: "linked rule")
        store.addRule(kind: .keep, pattern: "linkedtoken", language: .english, module: .spell) { saved.fulfill() }
        wait(for: [saved], timeout: 3)
        let existing = try XCTUnwrap(store.loadPersonalWords().first)
        let words = expectation(description: "word import keeps valid local rule link")
        store.importPersonalWords([existing]) { words.fulfill() }
        wait(for: [words], timeout: 3)
        XCTAssertEqual(store.loadPersonalWords().first?.ruleID, existing.ruleID)
        let deleted = expectation(description: "delete linked rule")
        store.deleteRule(id: try XCTUnwrap(existing.ruleID)) { deleted.fulfill() }
        wait(for: [deleted], timeout: 3)
        XCTAssertTrue(store.loadPersonalWords().isEmpty)
    }

    func testLegacyRulesRemainDecodableAndRussianYoIsNotMergedWithYe() throws {
        let original = UserRule(id: 1, kind: .keep, pattern: "всё", replacement: nil, language: .russian,
            applicationBundleIdentifier: nil, createdAt: Date())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserRule.self, from: data)
        XCTAssertTrue(decoded.isEnabled)
        let rules = RuleStore(); rules.replaceRules([decoded])
        XCTAssertEqual(rules.decision(original: "всё", alternative: "dc`", sourceLanguage: .russian, applicationBundleIdentifier: nil), .keep)
        XCTAssertNil(rules.decision(original: "все", alternative: "dct", sourceLanguage: .russian, applicationBundleIdentifier: nil))
        XCTAssertEqual(PersonalWordValidation.normalized("cafe\u{301}", language: .english), "café")
    }

    func testPersonalVocabularyCanCorrectANewTypoWithoutChangingKnownWords() {
        let suite = "PersonalVocabulary-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SpellPreferences.register(in: defaults)
        let rules = RuleStore()
        rules.replaceWords([PersonalWord(id: "personal", word: "zaza", language: .english,
            origin: .manual, applicationBundleIdentifier: nil, ruleID: nil, createdAt: Date())])
        let corrector = SpellCorrectionEngine(lexicon: NoWords(), defaults: defaults, rules: rules, application: { nil })
        XCTAssertNil(corrector.correction(for: "zaza"))
        XCTAssertEqual(corrector.correction(for: "zazaa")?.replacement, "zaza")
    }

    private func record(_ store: JournalStore, time: TimeInterval, id: String = UUID().uuidString) {
        let saved = expectation(description: "learning proof")
        store.recordProof(LearningProof(id: id, pattern: "ghbdtn", replacement: "привет", sourceLanguage: .english,
            targetLanguage: .russian, module: .switcher, kind: .convert, applicationBundleIdentifier: "com.example.Editor",
            confirmedAt: Date(timeIntervalSince1970: time))) { _ in saved.fulfill() }
        wait(for: [saved], timeout: 3)
    }
}

private final class NoWords: WordScoring {
    func score(for word: String, language: SpellLanguage) -> Int? { nil }
}
