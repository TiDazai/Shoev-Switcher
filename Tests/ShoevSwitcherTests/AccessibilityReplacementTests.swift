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
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
        XCTAssertEqual(editor.range.length, 0)
    }

    func testDeferredEditNeverSelectsOrReinsertsThePhysicalDelimiter() {
        for paste in [false, true] {
            let editor = DeferredEditor()
            editor.usePaste = paste
            editor.trimInsertedTrailingWhitespace = true
            let injector = editor.injector()
            let finished = expectation(description: "word-only correction, paste=\(paste)")
            editor.schedule(injector, completion: { finished.fulfill() })
            wait(for: [finished], timeout: 1)
            XCTAssertEqual(editor.text, "я привет ")
            XCTAssertEqual(editor.range.location, editor.text.utf16.count)
            XCTAssertEqual(editor.range.length, 0)
            XCTAssertEqual(editor.insertedValues, ["привет"])
            XCTAssertEqual(editor.replacedValues, ["ghbdtn"])
        }
    }

    func testCaretSetterAcknowledgedButDelayedIsRetried() {
        let editor = DeferredEditor()
        editor.ignoredCaretWrites = 2
        let injector = editor.injector()
        let finished = expectation(description: "caret really moved past space")
        editor.schedule(injector, completion: {
            XCTAssertEqual(editor.range.location, editor.text.utf16.count)
            finished.fulfill()
        })
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(editor.text, "я привет ")
        XCTAssertGreaterThanOrEqual(editor.caretWrites, 3)
    }

    func testUnconfirmedCaretDoesNotReportACompletedCorrection() {
        let editor = DeferredEditor()
        editor.ignoredCaretWrites = 100
        let injector = editor.injector()
        let finished = expectation(description: "no false caret confirmation")
        finished.isInverted = true
        editor.schedule(injector, completion: { finished.fulfill() })
        wait(for: [finished], timeout: 0.2)
        XCTAssertEqual(editor.text, "я привет ")
        XCTAssertEqual(editor.range.location, "я привет".utf16.count)
        XCTAssertEqual(editor.caretWrites, 8)
    }

    func testPunctuationAndTextAfterCaretRemainUntouched() {
        let editor = DeferredEditor()
        editor.text = "🙂 ghbdtn конец"
        editor.range = CFRange(location: "🙂 ghbdtn".utf16.count, length: 0)
        let injector = editor.injector()
        let finished = expectation(description: "punctuation and UTF16 caret")
        editor.schedule(injector, delimiter: ",", completion: { finished.fulfill() })
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(editor.text, "🙂 привет, конец")
        XCTAssertEqual(editor.range.location, "🙂 привет,".utf16.count)
        XCTAssertEqual(editor.replacedValues, ["ghbdtn"])
    }

    func testAppendOnlySpellEditPreservesExistingSpace() {
        let editor = DeferredEditor()
        editor.text = "например"
        editor.range = CFRange(location: editor.text.utf16.count, length: 0)
        let injector = editor.injector()
        let adapter = SpellTextInjector(injector: injector)
        let finished = expectation(description: "zero-delete spelling edit")
        let caret = CaretContext(prefix: editor.text, selectionLength: 0, nextCharacter: nil,
                                 element: editor.element, fullText: editor.text)
        XCTAssertFalse(adapter.replaceAfterDelimiter(deleteCount: 0, with: ",", trailingEvent: editor.event(" "),
            context: caret, completion: { finished.fulfill() }))
        editor.insertPhysical(" ")
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(editor.text, "например, ")
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
        XCTAssertEqual(editor.replacedValues, [""])
        XCTAssertEqual(editor.insertedValues, [","])
    }

    func testFollowingTypingCancelsPendingReplacement() {
        let editor = DeferredEditor()
        let injector = editor.injector()
        let finished = expectation(description: "do not overwrite following input")
        finished.isInverted = true
        editor.schedule(injector, completion: { finished.fulfill() })
        editor.insertPhysical("next")
        wait(for: [finished], timeout: 0.12)
        XCTAssertEqual(editor.text, "я ghbdtn next")
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
        XCTAssertTrue(editor.insertedValues.isEmpty)
    }

    func testTypingDuringCaretAcknowledgementIsNotPulledBack() {
        let editor = DeferredEditor()
        let injector = editor.injector()
        let finished = expectation(description: "continued input preserves caret")
        editor.afterInsert = {
            editor.range.location += 1 // The editor already placed it after the physical space.
            editor.insertPhysical("дальше")
        }
        editor.schedule(injector, completion: { finished.fulfill() })
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(editor.text, "я привет дальше")
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
        XCTAssertEqual(editor.caretWrites, 0)
    }

    func testMovedCaretCancelsPendingCaretRetry() {
        let editor = DeferredEditor()
        editor.ignoredCaretWrites = 1
        editor.onIgnoredCaretWrite = { editor.range = CFRange(location: 0, length: 0) }
        let injector = editor.injector()
        let finished = expectation(description: "do not move a user-positioned caret")
        finished.isInverted = true
        editor.schedule(injector, completion: { finished.fulfill() })
        wait(for: [finished], timeout: 0.12)
        XCTAssertEqual(editor.text, "я привет ")
        XCTAssertEqual(editor.range.location, 0)
        XCTAssertEqual(editor.caretWrites, 1)
    }

    func testCancellationStopsPendingCaretRetry() {
        let editor = DeferredEditor()
        editor.ignoredCaretWrites = 1
        let injector = editor.injector()
        editor.onIgnoredCaretWrite = { [weak injector] in injector?.cancelPending() }
        let finished = expectation(description: "cancelled caret task never completes")
        finished.isInverted = true
        editor.schedule(injector, completion: { finished.fulfill() })
        wait(for: [finished], timeout: 0.12)
        XCTAssertEqual(editor.text, "я привет ")
        XCTAssertEqual(editor.range.location, "я привет".utf16.count)
        XCTAssertEqual(editor.caretWrites, 1)
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

/// A control that can trim inserted payloads and acknowledge AX range writes
/// without applying them. No real app, keyboard or general pasteboard is touched.
private final class DeferredEditor {
    let element = AXUIElementCreateApplication(999_992)
    var text = "я ghbdtn"
    var range = CFRange(location: "я ghbdtn".utf16.count, length: 0)
    var usePaste = false
    var trimInsertedTrailingWhitespace = false
    var ignoredCaretWrites = 0
    var caretWrites = 0
    var insertedValues: [String] = []
    var replacedValues: [String] = []
    var afterInsert: (() -> Void)?
    var onIgnoredCaretWrite: (() -> Void)?
    var context: TextReplacementContext { TextReplacementContext(element: element, text: text, range: range) }

    func injector() -> EventInjector {
        var access = AccessibilityAccess()
        access.writable = { [unowned self] _, name in name == kAXSelectedTextRangeAttribute || !usePaste }
        access.set = { [unowned self] _, name, value in
            if name == kAXSelectedTextRangeAttribute {
                var requested = CFRange()
                AXValueGetValue(value as! AXValue, .cfRange, &requested)
                if !insertedValues.isEmpty, requested.length == 0 {
                    caretWrites += 1
                    if ignoredCaretWrites > 0 {
                        ignoredCaretWrites -= 1
                        onIgnoredCaretWrite?()
                        return .success
                    }
                }
                range = requested
            } else { apply(value as! String) }
            return .success
        }
        return EventInjector(access: access, readContext: { self.context }, secureInput: { false },
            pasteOverride: { [unowned self] inserted, selected, expected in
                XCTAssertTrue(context.matches(selected))
                apply(inserted)
                XCTAssertEqual(text, expected)
                return true
            })
    }

    func apply(_ value: String) {
        replacedValues.append((text as NSString).substring(with: NSRange(location: range.location, length: range.length)))
        insertedValues.append(value)
        let inserted = trimInsertedTrailingWhitespace ? value.trimmingCharacters(in: .whitespaces) : value
        text = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: inserted)
        range = CFRange(location: range.location + inserted.utf16.count, length: 0)
        afterInsert?()
    }

    func event(_ delimiter: String) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        let units = Array(delimiter.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        return event
    }

    func insertPhysical(_ text: String) {
        self.text = (self.text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
        range = CFRange(location: range.location + text.utf16.count, length: 0)
    }

    func schedule(_ injector: EventInjector, delimiter: String = " ", completion: @escaping () -> Void) {
        XCTAssertFalse(injector.replaceAfterDelimiter(original: "ghbdtn", with: "привет", trailingEvent: event(delimiter),
            context: context, completion: completion))
        insertPhysical(delimiter)
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
