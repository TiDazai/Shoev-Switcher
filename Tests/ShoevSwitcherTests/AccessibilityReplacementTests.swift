import AppKit
import XCTest
@testable import ShoevSwitcher

final class AccessibilityReplacementTests: XCTestCase {
    func testDeferredReplacementPreservesThePhysicalSpace() {
        let editor = FakeEditor()
        var access = AccessibilityAccess()
        access.writable = { _, _ in true }
        access.set = { _, name, value in
            if name == kAXSelectedTextRangeAttribute {
                AXValueGetValue(value as! AXValue, .cfRange, &editor.range)
            } else { editor.apply(value as! String) }
            return .success
        }
        let injector = EventInjector(access: access, readContext: { editor.context }, secureInput: { false })
        let finished = expectation(description: "confirmed deferred edit")
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [32])
        XCTAssertFalse(injector.replaceAfterDelimiter(original: "ghbdtn", with: "привет",
            trailingEvent: event, context: editor.context, completion: { finished.fulfill() }))
        XCTAssertEqual(editor.text, "я ghbdtn")
        editor.text += " "
        editor.range.location += 1
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(editor.text, "я привет ")
    }

    func testNativeReplacementIsPreferred() {
        let editor = FakeEditor()
        XCTAssertTrue(editor.replace())
        XCTAssertEqual(editor.text, "я привет ")
        XCTAssertEqual(editor.pastes, 0)
    }
    func testIgnoredNativeSetterUsesPasteWithConfirmedRange() {
        let editor = FakeEditor()
        editor.ignoreNative = true
        XCTAssertTrue(editor.replace())
        XCTAssertEqual(editor.text, "я привет ")
        XCTAssertEqual(editor.pastes, 1)
    }
    func testReadOnlyTextUsesPasteButNotReadOnlySelection() {
        let editor = FakeEditor()
        editor.writableText = false
        XCTAssertTrue(editor.replace())
        XCTAssertEqual(editor.pastes, 1)
        let readOnly = FakeEditor()
        readOnly.writableSelection = false
        XCTAssertFalse(readOnly.replace())
        XCTAssertEqual(readOnly.pastes, 0)
        XCTAssertEqual(readOnly.text, "я ghbdtn")
    }
    func testRefusedPasteRestoresCaretAndPreservesDelimiter() {
        let editor = FakeEditor()
        editor.ignoreNative = true
        editor.refusePaste = true
        XCTAssertFalse(editor.replace())
        XCTAssertEqual(editor.text, "я ghbdtn")
        XCTAssertEqual(editor.range.length, 0)
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
    }
    func testPartialNativeEditIsNeverOverwrittenByPaste() {
        let editor = FakeEditor()
        editor.partialNative = true
        XCTAssertTrue(editor.replace())
        XCTAssertEqual(editor.text, "changed externally")
        XCTAssertEqual(editor.pastes, 0)
    }
    func testSecureInputAndEnterAreNeverInjected() {
        let editor = FakeEditor()
        editor.secure = true
        XCTAssertFalse(editor.replace())
        editor.secure = false
        XCTAssertFalse(editor.replace(delimiter: "\r"))
        XCTAssertEqual(editor.pastes, 0)
        XCTAssertEqual(editor.text, "я ghbdtn")
    }
}

private final class FakeEditor {
    let element = AXUIElementCreateApplication(999_991)
    var text = "я ghbdtn"
    var range = CFRange(location: "я ghbdtn".utf16.count, length: 0)
    var ignoreNative = false
    var partialNative = false
    var writableText = true
    var writableSelection = true
    var refusePaste = false
    var secure = false
    var pastes = 0
    var context: TextReplacementContext { TextReplacementContext(element: element, text: text, range: range) }
    func apply(_ value: String) {
        text = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: value)
        range = CFRange(location: range.location + value.utf16.count, length: 0)
    }
    func replace(delimiter: String = " ") -> Bool {
        var access = AccessibilityAccess()
        access.writable = { [unowned self] _, name in
            name == kAXSelectedTextRangeAttribute ? writableSelection : writableText
        }
        access.set = { [unowned self] _, name, value in
            if name == kAXSelectedTextRangeAttribute {
                AXValueGetValue(value as! AXValue, .cfRange, &range)
            } else if partialNative {
                text = "changed externally"
            } else if !ignoreNative, let value = value as? String { apply(value) }
            return .success
        }
        let injector = EventInjector(access: access, readContext: { self.context }, secureInput: { self.secure },
            pasteOverride: { [unowned self] inserted, selected, expected in
                XCTAssertTrue(context.matches(selected))
                XCTAssertEqual(selected.range.length, 6)
                if refusePaste { return false }
                pastes += 1
                apply(inserted)
                XCTAssertEqual(text, expected)
                return true
            })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        let units = Array(delimiter.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        return injector.replace(original: "ghbdtn", with: "привет", trailingEvent: event, context: context)
    }
}
