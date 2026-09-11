import Foundation
import XCTest
@testable import ShoevSwitcher

final class JournalStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShoevSwitcherTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testJournalRoundTrip() throws {
        let store = try JournalStore(baseDirectory: temporaryDirectory)
        store.enqueue(JournalEntry(
            id: 0,
            createdAt: Date(timeIntervalSince1970: 1_234),
            applicationBundleIdentifier: "com.example.Editor",
            applicationName: "Editor",
            original: "ghbdtn",
            replacement: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            kind: .correction
        ))

        let loaded = expectation(description: "Loaded journal")
        store.recentEntries { entries in
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first?.original, "ghbdtn")
            XCTAssertEqual(entries.first?.replacement, "привет")
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 3)
    }

    func testRulesRoundTrip() throws {
        let store = try JournalStore(baseDirectory: temporaryDirectory)
        let inserted = expectation(description: "Inserted rule")
        store.addRule(
            kind: .convert,
            pattern: "ghbdtn",
            replacement: "привет",
            language: .english,
            applicationBundleIdentifier: nil
        ) {
            inserted.fulfill()
        }
        wait(for: [inserted], timeout: 3)

        let rules = store.loadRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.pattern, "ghbdtn")
        XCTAssertEqual(rules.first?.replacement, "привет")
    }

    func testSecondManualConversionCreatesLearnedRule() throws {
        let store = try JournalStore(baseDirectory: temporaryDirectory)
        let first = expectation(description: "First observation")
        store.recordManualConversion(
            original: "ghbdtn",
            replacement: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian
        ) { learned in
            XCTAssertFalse(learned)
            first.fulfill()
        }
        wait(for: [first], timeout: 3)

        let second = expectation(description: "Second observation")
        store.recordManualConversion(
            original: "ghbdtn",
            replacement: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian
        ) { learned in
            XCTAssertTrue(learned)
            second.fulfill()
        }
        wait(for: [second], timeout: 3)

        let rules = store.loadRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].kind, .convert)
        XCTAssertEqual(rules[0].pattern, "ghbdtn")
        XCTAssertEqual(rules[0].replacement, "привет")
        XCTAssertEqual(rules[0].language, .english)
    }

    func testRuleCanBeUpdatedDeletedAndImportedWithoutDuplicates() throws {
        let store = try JournalStore(baseDirectory: temporaryDirectory)
        let inserted = expectation(description: "Inserted")
        store.addRule(kind: .keep, pattern: "OpenAI", language: .english) {
            inserted.fulfill()
        }
        wait(for: [inserted], timeout: 3)
        var rule = try XCTUnwrap(store.loadRules().first)

        let updated = expectation(description: "Updated")
        rule = UserRule(
            id: rule.id,
            kind: .accept,
            pattern: "OpenAI",
            replacement: nil,
            language: .english,
            applicationBundleIdentifier: nil,
            createdAt: rule.createdAt
        )
        store.updateRule(rule) { updated.fulfill() }
        wait(for: [updated], timeout: 3)
        XCTAssertEqual(store.loadRules().first?.kind, .accept)

        let duplicateImport = expectation(description: "Duplicate import")
        store.importRules([rule]) { count in
            XCTAssertEqual(count, 0)
            duplicateImport.fulfill()
        }
        wait(for: [duplicateImport], timeout: 3)

        let deleted = expectation(description: "Deleted")
        store.deleteRule(id: rule.id) { deleted.fulfill() }
        wait(for: [deleted], timeout: 3)
        XCTAssertTrue(store.loadRules().isEmpty)
    }
}
