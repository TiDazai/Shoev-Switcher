import XCTest
@testable import ShoevSwitcher

final class DictionaryCatalogTests: XCTestCase {
    func testBothHugeCorporaCanBeBrowsedWithoutMaterializingThem() {
        let catalog = DictionaryCatalog()
        for (language, count) in [(InputLanguage.russian, 4_020_787), (.english, 3_100_152)] {
            let loaded = expectation(description: "small indexed page")
            catalog.page(language: language, limit: 20) { page in
                XCTAssertEqual(page.builtinCount, count)
                XCTAssertEqual(page.rows.count, 20); XCTAssertTrue(page.hasNext)
                loaded.fulfill()
            }
            wait(for: [loaded], timeout: 5)
        }
    }
    func testPrefixSearchAndKeysetPaginationDoNotRepeatWords() {
        let catalog = DictionaryCatalog()
        let loaded = expectation(description: "two pages")
        catalog.page(language: .english, prefix: "hello", limit: 3) { first in
            XCTAssertTrue(first.rows.allSatisfy { $0.word.hasPrefix("hello") })
            catalog.page(language: .english, prefix: "hello", after: first.rows.last?.word, limit: 3) { second in
                XCTAssertTrue(Set(first.rows.map(\.word)).isDisjoint(with: Set(second.rows.map(\.word))))
                loaded.fulfill()
            }
        }
        wait(for: [loaded], timeout: 5)
    }
    func testPersonalWordsAreVisibleMarkedAndBuiltinMatchesNotDuplicated() {
        let catalog = DictionaryCatalog()
        let custom = [PersonalWord(id: "1", word: "hello", language: .english, origin: .learning,
            applicationBundleIdentifier: nil, ruleID: 1, createdAt: Date()),
            PersonalWord(id: "2", word: "hellozzzpersonaltoken", language: .english, origin: .manual,
            applicationBundleIdentifier: nil, ruleID: nil, createdAt: Date())]
        let loaded = expectation(description: "marked personal view")
        catalog.page(language: .english, prefix: "hello", source: .personal, personal: custom) { page in
            XCTAssertEqual(page.rows.count, 2); XCTAssertEqual(page.personalCount, 2)
            XCTAssertEqual(page.rows.first(where: { $0.word == "hello" })?.builtin, true)
            XCTAssertEqual(page.rows.first(where: { $0.word == "hello" })?.personal.first?.origin, .learning)
            XCTAssertEqual(page.rows.first(where: { $0.word == "hellozzzpersonaltoken" })?.builtin, false)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
    }
}
