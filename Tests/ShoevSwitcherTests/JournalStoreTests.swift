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
}
