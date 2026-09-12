import XCTest
@testable import ShoevSwitcher

final class InputSourceManagerTests: XCTestCase {
    func testConvertsWholeSelectedTextInBothDirections() {
        let manager = InputSourceManager()
        XCTAssertEqual(
            manager.convertedText("Ghbdtn vbh", from: .english, to: .russian),
            "Привет мир"
        )
        XCTAssertEqual(
            manager.convertedText("Привет мир", from: .russian, to: .english),
            "Ghbdtn vbh"
        )
    }

    func testSelectionLanguageIsDetectedFromItsLetters() {
        XCTAssertEqual(TextSelectionConverter.detectedLanguage(in: "ghbdtn"), .english)
        XCTAssertEqual(TextSelectionConverter.detectedLanguage(in: "привет"), .russian)
        XCTAssertNil(TextSelectionConverter.detectedLanguage(in: "123 — !"))
    }

    func testWrongLayoutSequencePreservesRussianLetterOnCommaKey() throws {
        let manager = InputSourceManager()
        guard manager.russianSource != nil else {
            throw XCTSkip("Russian input source is not enabled on this Mac")
        }

        let strokes = [
            KeyStroke(keyCode: 4, visibleText: "h"),
            KeyStroke(keyCode: 3, visibleText: "f"),
            KeyStroke(keyCode: 43, visibleText: ","),
            KeyStroke(keyCode: 38, visibleText: "j"),
            KeyStroke(keyCode: 45, visibleText: "n"),
            KeyStroke(keyCode: 3, visibleText: "f"),
            KeyStroke(keyCode: 17, visibleText: "t"),
            KeyStroke(keyCode: 45, visibleText: "n")
        ]

        XCTAssertEqual(manager.text(for: strokes, in: .russian), "работает")
        XCTAssertTrue(manager.isPotentialWordStroke(strokes[2]))
    }

    func testPhysicalEnglishKeySequenceTranslatesToRussian() throws {
        let manager = InputSourceManager()
        guard manager.russianSource != nil else {
            throw XCTSkip("Russian input source is not enabled on this Mac")
        }
        let strokes = [
            KeyStroke(keyCode: 5, visibleText: "g", shouldUppercase: true),
            KeyStroke(keyCode: 4, visibleText: "h"),
            KeyStroke(keyCode: 11, visibleText: "b"),
            KeyStroke(keyCode: 2, visibleText: "d"),
            KeyStroke(keyCode: 17, visibleText: "t"),
            KeyStroke(keyCode: 45, visibleText: "n")
        ]
        XCTAssertEqual(manager.text(for: strokes, in: .russian), "Привет")
    }
}
