import AppKit
import XCTest
@testable import ShoevSwitcher

final class PasteboardSnapshotTests: XCTestCase {
    func testRestoresAllFormatsAndItems() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("original", forType: .string)
        let richText = Data("{\\rtf1\\ansi original}".utf8)
        first.setData(richText, forType: .rtf)
        let second = NSPasteboardItem()
        second.setString("https://example.invalid", forType: .URL)
        XCTAssertTrue(board.writeObjects([first, second]))
        let snapshot = try XCTUnwrap(PasteboardSnapshot.capture(board))
        board.clearContents()
        board.setString("correction", forType: .string)
        XCTAssertTrue(snapshot.restore(board, ifOwned: board.changeCount))
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        XCTAssertEqual(board.pasteboardItems?.first?.string(forType: .string), "original")
        XCTAssertEqual(board.pasteboardItems?.first?.data(forType: .rtf), richText)
        XCTAssertEqual(board.pasteboardItems?.last?.string(forType: .URL), "https://example.invalid")
    }

    func testNewUserCopyIsNeverOverwritten() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot.capture(board)!
        board.clearContents()
        board.setString("correction", forType: .string)
        let owned = board.changeCount
        board.clearContents()
        board.setString("new user copy", forType: .string)
        XCTAssertFalse(snapshot.restore(board, ifOwned: owned))
        XCTAssertEqual(board.string(forType: .string), "new user copy")
    }

    func testEmptyPasteboardIsRestoredEmpty() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        let snapshot = PasteboardSnapshot.capture(board)!
        board.setString("correction", forType: .string)
        XCTAssertTrue(snapshot.restore(board, ifOwned: board.changeCount))
        XCTAssertNil(board.string(forType: .string))
    }

    func testOversizedClipboardIsNotUsedForCorrections() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setData(Data(repeating: 0, count: 8 * 1024 * 1024 + 1), forType: .png)
        XCTAssertNil(PasteboardSnapshot.capture(board))
    }
}
