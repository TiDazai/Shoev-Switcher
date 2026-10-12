import XCTest
@testable import ShoevSwitcher

final class CapitalizationContextTests: XCTestCase {
    func testManualEditingDoesNotStartSentence() {
        for prefix in ["при", "Например я ду", "слово ", "слово, ", "слово: ", "слово; "] {
            XCTAssertFalse(CapitalizationContext.shouldCapitalize(after: prefix), prefix)
        }
    }

    func testFieldAndSentenceStarts() {
        for prefix in ["", "   ", "\n", "Первая строка\n  ", "Готово. ", "Готово.", "Да! ", "Почему? ", "Постой… ", "Он сказал: «Да!» "] {
            XCTAssertTrue(CapitalizationContext.shouldCapitalize(after: prefix), prefix)
        }
    }

    func testQuotes() {
        for prefix in ["«", "Он сказал: «", "„", "“", "\"", "Он сказал: \""] {
            XCTAssertTrue(CapitalizationContext.shouldCapitalize(after: prefix), prefix)
        }
        for prefix in ["«сло", "«слово» ", "\"слово\" "] {
            XCTAssertFalse(CapitalizationContext.shouldCapitalize(after: prefix), prefix)
        }
    }

    func testAbbreviationsInitialsAndNumbers() {
        for prefix in ["ул. ", "см. ", "А. ", "т. е. ", "3.", "Версия 1.2.", "example.com."] {
            XCTAssertFalse(CapitalizationContext.shouldCapitalize(after: prefix), prefix)
        }
    }

    func testCaretInsideWord() {
        XCTAssertTrue(CaretContext(prefix: "при", selectionLength: 0).startsInsideWord)
        XCTAssertFalse(CaretContext(prefix: "привет ", selectionLength: 0).startsInsideWord)
        XCTAssertTrue(CaretContext(prefix: "привет ", selectionLength: 0, nextCharacter: "м").startsInsideWord)
    }
}
