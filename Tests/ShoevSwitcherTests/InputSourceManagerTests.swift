import XCTest
@testable import ShoevSwitcher

final class InputSourceManagerTests: XCTestCase {
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
}
