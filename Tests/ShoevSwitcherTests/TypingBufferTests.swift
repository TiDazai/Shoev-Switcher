import CoreGraphics
import XCTest
@testable import ShoevSwitcher

final class TypingBufferTests: XCTestCase {
    func testBuildsAndCompletesToken() {
        var buffer = TypingBuffer()
        buffer.append(KeyStroke(keyCode: 4, visibleText: "h"))
        buffer.append(KeyStroke(keyCode: 14, visibleText: "e"))
        XCTAssertEqual(buffer.current.visibleText, "he")

        buffer.complete(
            displayedText: "he",
            alternativeText: "ру",
            displayedLanguage: .english,
            alternativeLanguage: .russian,
            terminator: " ",
            processIdentifier: 123
        )

        XCTAssertTrue(buffer.current.isEmpty)
        XCTAssertEqual(buffer.lastCompleted?.displayedText, "he")
        XCTAssertEqual(buffer.lastCompleted?.terminator, " ")
    }

    func testBackspaceRemovesOneStroke() {
        var buffer = TypingBuffer()
        buffer.append(KeyStroke(keyCode: 0, visibleText: "a"))
        buffer.append(KeyStroke(keyCode: 11, visibleText: "b"))
        buffer.backspace()
        XCTAssertEqual(buffer.current.visibleText, "a")
    }
}
