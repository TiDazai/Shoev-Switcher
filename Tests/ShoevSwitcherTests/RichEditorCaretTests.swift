import AppKit
import XCTest
@testable import ShoevSwitcher

final class RichEditorCaretTests: XCTestCase {
    func testEmptyWritableEditorHasOnlyOnePossibleCaretPosition() throws {
        let field = RichField()
        let context = try XCTUnwrap(field.read())
        XCTAssertEqual(context.prefix, ""); XCTAssertEqual(context.selectionLength, 0)
        XCTAssertEqual(context.selectionTransport, .range)
    }

    func testReadOnlyEmptyFieldDoesNotInventACaret() {
        let field = RichField(); field.editable = false
        XCTAssertNil(field.read())
    }

    func testPopulatedEditorWithoutRangeDoesNotInventACaret() {
        let field = RichField(); field.text = "existing word"
        XCTAssertNil(field.read())
    }

    func testSecureEmptyEditorNeverReadsItsValue() {
        let field = RichField(); field.secure = true
        XCTAssertNil(field.read()); XCTAssertEqual(field.valueReads, 0)
    }

    func testInvalidReportedRangeIsNotReplacedByAnAssumedEmptyCaret() {
        let field = RichField(); field.reportRange = true; field.range = CFRange(location: 1, length: 0)
        XCTAssertNil(field.read())
    }

    func testArrayOnlySelectionIsReadAndWrittenWithoutChangingText() throws {
        let field = RichField(); field.arrayOnly = true; field.reportRange = true
        field.text = "превет"; field.range = CFRange(location: 6, length: 0)
        let caret = try XCTUnwrap(field.read())
        XCTAssertEqual(caret.selectionTransport, .ranges)
        let context = TextReplacementContext(element: field.element, text: field.text, range: field.range, selectionTransport: .ranges)
        let selection = AccessibilityTextSelection(access: field.access)
        XCTAssertTrue(selection.canSet(context))
        XCTAssertTrue(selection.set(CFRange(location: 0, length: 6), in: context))
        XCTAssertEqual(field.range.length, 6); XCTAssertEqual(field.text, "превет")
        XCTAssertEqual(field.writtenAttribute, kAXSelectedTextRangesAttribute)
    }

    func testEmptyArrayOnlyEditorKeepsTheSameTransportAsItsFirstWord() throws {
        let field = RichField(); field.arrayOnly = true
        let before = try XCTUnwrap(field.read())
        field.text = "п"; field.reportRange = true; field.range = CFRange(location: 1, length: 0)
        let after = try XCTUnwrap(field.read())
        XCTAssertTrue(before.sameField(as: after)); XCTAssertEqual(before.selectionTransport, .ranges)
    }

    func testMultipleSelectionsAreNeverEdited() {
        let field = RichField(); field.arrayOnly = true; field.reportRange = true; field.multiple = true
        XCTAssertNil(field.read()); XCTAssertEqual(field.valueReads, 0)
    }

    func testMalformedSelectionArrayDoesNotInventAnEmptyCaret() {
        let field = RichField(); field.malformed = true
        XCTAssertNil(field.read())
    }

    func testEditableGroupIsRecognizedAsAContentEditableField() throws {
        let field = RichField(); field.role = kAXGroupRole; field.explicitEditable = true
        XCTAssertEqual(try XCTUnwrap(field.read()).prefix, "")
    }

    func testApplicationFocusIsUsedForCodexToo() throws {
        let field = RichField()
        let reader = VerifiedCaretContextReader(access: field.access, diagnostic: { _ in },
            focusedApplication: { (999_981, "com.openai.codex") })
        XCTAssertEqual(try XCTUnwrap(reader.read()).prefix, "")
        XCTAssertEqual(field.focusReads, 1)
    }

    func testFocusFromAnotherProcessIsNeverRead() {
        let field = RichField(); field.owner = 999_982
        let reader = VerifiedCaretContextReader(access: field.access, diagnostic: { _ in },
            focusedApplication: { (999_981, "com.openai.codex") })
        XCTAssertNil(reader.read()); XCTAssertEqual(field.valueReads, 0)
    }
}

private final class RichField {
    let element = AXUIElementCreateApplication(999_981)
    var owner: pid_t = 999_981
    var text = ""
    var range = CFRange(location: 0, length: 0)
    var role = kAXTextAreaRole
    var reportRange = false
    var arrayOnly = false
    var multiple = false
    var malformed = false
    var editable = true
    var explicitEditable = false
    var secure = false
    var valueReads = 0
    var focusReads = 0
    var writtenAttribute: String?
    var access: AccessibilityAccess {
        var access = AccessibilityAccess()
        access.processID = { _ in self.owner }
        access.copy = { [unowned self] _, name in
            switch name {
            case kAXFocusedUIElementAttribute: focusReads += 1; return element
            case kAXRoleAttribute: return role as CFString
            case kAXSubroleAttribute: return secure ? kAXSecureTextFieldSubrole as CFString : nil
            case "AXEditable": return explicitEditable ? kCFBooleanTrue : nil
            case kAXValueAttribute: valueReads += 1; return text as CFString
            case kAXSelectedTextRangeAttribute:
                return reportRange && !arrayOnly ? AXValueCreate(.cfRange, &range) : nil
            case kAXSelectedTextRangesAttribute:
                if malformed { return "invalid" as CFString }
                guard arrayOnly else { return nil }
                guard reportRange else { return [] as CFArray }
                let value = AXValueCreate(.cfRange, &range)!
                return multiple ? [value, value] as CFArray : [value] as CFArray
            default: return nil
            }
        }
        access.parameter = { _, _, _ in nil }
        access.parameterNames = { _ in [] }
        access.writable = { [unowned self] _, name in
            if name == kAXValueAttribute || name == kAXSelectedTextAttribute { return editable }
            return name == (arrayOnly ? kAXSelectedTextRangesAttribute : kAXSelectedTextRangeAttribute)
        }
        access.set = { [unowned self] _, name, value in
            writtenAttribute = name
            let raw = arrayOnly ? (value as! [CFTypeRef]).first! : value
            AXValueGetValue(raw as! AXValue, .cfRange, &range)
            return .success
        }
        return access
    }
    func read() -> CaretContext? { VerifiedCaretContextReader(access: access, diagnostic: { _ in }).read(focusedElement: element) }
}
