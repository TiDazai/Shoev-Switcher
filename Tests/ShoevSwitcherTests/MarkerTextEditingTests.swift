import AppKit
import XCTest
@testable import ShoevSwitcher

final class MarkerTextEditingTests: XCTestCase {
    func testReadsOnlyTheCurrentParagraphWithUTF16Coordinates() throws {
        let editor = MarkerEditor()
        editor.text = "🙂 превет конец"
        editor.range = CFRange(location: "🙂 превет".utf16.count, length: 0)
        editor.offset = 120_000
        let caret = try XCTUnwrap(editor.reader.read(focusedElement: editor.element))
        XCTAssertEqual(caret.prefix, "🙂 превет")
        XCTAssertEqual(caret.nextCharacter, " ")
        XCTAssertEqual(caret.textOffset, 120_000)
        XCTAssertEqual(caret.selectionTransport, .markers)
        XCTAssertEqual(editor.stringReads, 1)
    }

    func testSmallDocumentFallbackWhenParagraphAPIMissing() {
        let editor = MarkerEditor(); editor.paragraphAPI = false; editor.offset = 0
        XCTAssertNotNil(editor.reader.read(focusedElement: editor.element))
    }

    func testLargeParagraphIsRejectedBeforeAnyTextRead() {
        let editor = MarkerEditor(); editor.reportedLength = 100_000
        XCTAssertNil(editor.reader.read(focusedElement: editor.element))
        XCTAssertEqual(editor.stringReads, 0)
    }

    func testLongDocumentWithoutParagraphAPIIsNotRead() {
        let editor = MarkerEditor(); editor.paragraphAPI = false; editor.reportedLength = 100_000
        XCTAssertNil(editor.reader.read(focusedElement: editor.element))
        XCTAssertEqual(editor.stringReads, 0)
    }

    func testSecureFieldNeverReadsMarkers() {
        let editor = MarkerEditor(); editor.secure = true
        XCTAssertNil(editor.reader.read(focusedElement: editor.element))
        XCTAssertEqual(editor.markerReads, 0); XCTAssertEqual(editor.stringReads, 0)
    }

    func testWordUsesApplicationFocusBeforeSystemFocus() {
        let editor = MarkerEditor()
        let reader = VerifiedCaretContextReader(access: editor.access, diagnostic: { _ in },
            focusedApplication: { (999_987, "com.microsoft.Word") })
        XCTAssertEqual(reader.read()?.prefix, "превет")
        XCTAssertEqual(editor.focusReads, 1)
    }

    func testSecureWordFocusDoesNotFallBackToAnotherField() {
        let editor = MarkerEditor(); editor.secure = true
        let reader = VerifiedCaretContextReader(access: editor.access, diagnostic: { _ in },
            focusedApplication: { (999_987, "com.microsoft.Word") })
        XCTAssertNil(reader.read())
        XCTAssertEqual(editor.focusReads, 1); XCTAssertEqual(editor.markerReads, 0)
    }

    func testMismatchedStringLengthIsNotTrusted() {
        let editor = MarkerEditor(); editor.reportedLength = editor.text.utf16.count + 1
        XCTAssertNil(editor.reader.read(focusedElement: editor.element))
    }

    func testExpiredBudgetDoesNotReadTheDocument() {
        let editor = MarkerEditor()
        XCTAssertNil(AccessibilityTextSelection(access: editor.access, deadline: 0).readMarkerContext(in: editor.element))
        XCTAssertEqual(editor.stringReads, 0); XCTAssertEqual(editor.markerReads, 0)
    }

    func testSelectionOutsideParagraphIsRejected() {
        let editor = MarkerEditor(); editor.range.length = 2
        XCTAssertNil(editor.reader.read(focusedElement: editor.element))
        XCTAssertEqual(editor.stringReads, 0)
    }

    func testMarkerRoundTripMustMatchBeforeWritingSelection() throws {
        let editor = MarkerEditor()
        let context = try XCTUnwrap(editor.context)
        editor.shiftGeneratedMarkers = true
        XCTAssertFalse(AccessibilityTextSelection(access: editor.access).set(CFRange(location: 0, length: 1), in: context))
        XCTAssertEqual(editor.selectionWrites, 0)
    }

    func testMarkerReplacementPreservesPhysicalSpaceAndFollowingText() throws {
        for ignored in [false, true] {
            let editor = MarkerEditor(); editor.ignoreNative = ignored
            editor.text = "🙂 превет конец"; editor.range = CFRange(location: "🙂 превет".utf16.count, length: 0)
            let before = try XCTUnwrap(editor.context)
            let injector = editor.injector()
            let done = expectation(description: "confirmed marker replacement")
            XCTAssertFalse(injector.replaceAfterDelimiter(original: "превет", with: "привет",
                trailingEvent: editor.space(), context: before, completion: { done.fulfill() }))
            editor.insertPhysical(" ")
            wait(for: [done], timeout: 2)
            XCTAssertEqual(editor.text, "🙂 привет  конец")
            XCTAssertEqual(editor.range.location, "🙂 привет ".utf16.count)
            XCTAssertEqual(editor.inserted, ["привет"])
            XCTAssertEqual(editor.replaced, ["превет"])
            XCTAssertEqual(editor.pastes, ignored ? 1 : 0)
        }
    }

    func testChangedParagraphCancelsDeferredEditEvenWithIdenticalText() throws {
        let editor = MarkerEditor(); let injector = editor.injector()
        var completed = false
        XCTAssertFalse(injector.replaceAfterDelimiter(original: "превет", with: "привет",
            trailingEvent: editor.space(), context: try XCTUnwrap(editor.context), completion: { completed = true }))
        editor.insertPhysical(" "); editor.offset += 500
        let tick = expectation(description: "deferred check finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tick.fulfill() }
        wait(for: [tick], timeout: 2)
        XCTAssertFalse(completed); XCTAssertTrue(editor.inserted.isEmpty)
    }

    func testNativeWordCapitalizationDoesNotCancelSpellingCorrection() throws {
        let editor = MarkerEditor(); let injector = editor.injector()
        let done = expectation(description: "native capitalization is preserved")
        XCTAssertFalse(injector.replaceAfterDelimiter(original: "превет", with: "Привет",
            trailingEvent: editor.space(), context: try XCTUnwrap(editor.context), completion: { done.fulfill() }))
        editor.insertPhysical(" "); editor.text = "Превет "
        wait(for: [done], timeout: 2)
        XCTAssertEqual(editor.text, "Привет "); XCTAssertEqual(editor.replaced, ["Превет"])
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
    }

    func testNativeWordRewriteAndFollowingInputAreNotCaseNormalization() throws {
        let editor = MarkerEditor(); let before = try XCTUnwrap(editor.context)
        editor.insertPhysical(" "); editor.text = "Привет "
        XCTAssertNil(EventInjector.acknowledgedOriginal(context: before, after: try XCTUnwrap(editor.context),
            original: "превет", delimiter: " ", allowingCaseNormalization: true))
        editor.text = "Превет "; editor.insertPhysical("а")
        XCTAssertNil(EventInjector.acknowledgedOriginal(context: before, after: try XCTUnwrap(editor.context),
            original: "превет", delimiter: " ", allowingCaseNormalization: true))
    }

    func testCaseNormalizationIsNotEnabledForOtherEditors() throws {
        let editor = MarkerEditor(); let before = try XCTUnwrap(editor.context)
        editor.insertPhysical(" "); editor.text = "Превет "
        XCTAssertNil(EventInjector.acknowledgedOriginal(context: before, after: try XCTUnwrap(editor.context),
            original: "превет", delimiter: " ", allowingCaseNormalization: false))
    }

    func testReadOnlyMarkerSelectionNeverPastes() throws {
        let editor = MarkerEditor(); editor.selectionWritable = false
        XCTAssertFalse(editor.injector().replace(original: "превет", with: "привет", context: try XCTUnwrap(editor.context)))
        XCTAssertEqual(editor.pastes, 0); XCTAssertEqual(editor.selectionWrites, 0)
    }

    func testCaretAndReplacementContextsDoNotMatchDifferentParagraphs() {
        let editor = MarkerEditor()
        var a = CaretContext(prefix: "превет", selectionLength: 0, element: editor.element, fullText: "превет")
        a.selectionTransport = .markers; a.textOffset = 200
        var b = a; b.textOffset = 500
        XCTAssertFalse(a.matches(b)); XCTAssertFalse(a.sameField(as: b))
        let first = TextReplacementContext(element: editor.element, text: "превет", range: CFRange(location: 6, length: 0), textOffset: 200, selectionTransport: .markers)
        var second = first; second.textOffset = 500
        XCTAssertFalse(first.matches(second)); XCTAssertFalse(first.sameRegion(as: second))
    }
}

/// Opaque markers belong to this fake editor only. No live process or clipboard
/// is queried, and text-marker payloads in the application are never decoded.
private final class MarkerEditor {
    let element = AXUIElementCreateApplication(999_987)
    var text = "превет"
    var range = CFRange(location: 6, length: 0)
    var offset = 10_000
    var secure = false
    var paragraphAPI = true
    var reportedLength: Int?
    var shiftGeneratedMarkers = false
    var selectionWritable = true
    var ignoreNative = false
    var stringReads = 0
    var markerReads = 0
    var focusReads = 0
    var selectionWrites = 0
    var pastes = 0
    var inserted: [String] = []
    var replaced: [String] = []

    func marker(_ index: Int) -> AXTextMarker {
        var payload = Int64(index)
        return withUnsafeBytes(of: &payload) { AXTextMarkerCreate(kCFAllocatorDefault, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), $0.count) }
    }
    func index(_ marker: AXTextMarker) -> Int {
        var result: Int64 = 0
        withUnsafeMutableBytes(of: &result) { $0.copyMemory(from: UnsafeRawBufferPointer(start: AXTextMarkerGetBytePtr(marker), count: MemoryLayout<Int64>.size)) }
        return Int(result)
    }
    func markers(_ range: CFRange) -> AXTextMarkerRange {
        AXTextMarkerRangeCreate(kCFAllocatorDefault, marker(range.location), marker(range.location + range.length))
    }
    var access: AccessibilityAccess {
        var access = AccessibilityAccess()
        access.copy = { [unowned self] _, name in
            switch name {
            case kAXFocusedUIElementAttribute: focusReads += 1; return element
            case kAXSubroleAttribute: return secure ? kAXSecureTextFieldSubrole as CFString : nil
            case kAXRoleAttribute: return kAXTextAreaRole as CFString
            case "AXSelectedTextMarkerRange":
                markerReads += 1; return markers(CFRange(location: offset + range.location, length: range.length))
            case "AXStartTextMarker": return marker(offset)
            case "AXEndTextMarker": return marker(offset + (reportedLength ?? text.utf16.count))
            default: return nil
            }
        }
        access.parameter = { [unowned self] _, name, value in
            switch name {
            case "AXIndexForTextMarker": return NSNumber(value: index(value as! AXTextMarker))
            case "AXTextMarkerForIndex":
                return marker((value as! NSNumber).intValue + (shiftGeneratedMarkers ? 1 : 0))
            case "AXParagraphTextMarkerRangeForTextMarker":
                return paragraphAPI ? markers(CFRange(location: offset, length: reportedLength ?? text.utf16.count)) : nil
            case "AXStringForTextMarkerRange": stringReads += 1; return text as CFString
            default: return nil
            }
        }
        access.writable = { [unowned self] _, name in
            name == kAXSelectedTextMarkerRangeAttribute as String ? selectionWritable : name == kAXSelectedTextAttribute
        }
        access.set = { [unowned self] _, name, value in
            if name == kAXSelectedTextMarkerRangeAttribute as String {
                let requested = value as! AXTextMarkerRange
                let start = index(AXTextMarkerRangeCopyStartMarker(requested))
                let end = index(AXTextMarkerRangeCopyEndMarker(requested))
                range = CFRange(location: start - offset, length: end - start); selectionWrites += 1
            } else if name == kAXSelectedTextAttribute, !ignoreNative { apply(value as! String) }
            return .success
        }
        return access
    }
    var reader: VerifiedCaretContextReader { VerifiedCaretContextReader(access: access, diagnostic: { _ in }) }
    var context: TextReplacementContext? {
        guard let caret = reader.read(focusedElement: element), let fullText = caret.fullText else { return nil }
        return TextReplacementContext(element: element, text: fullText, range: CFRange(location: caret.prefix.utf16.count, length: caret.selectionLength), textOffset: caret.textOffset, selectionTransport: caret.selectionTransport)
    }
    func injector() -> EventInjector {
        EventInjector(access: access, readContext: { self.context }, secureInput: { false },
            pasteOverride: { [unowned self] value, selected, expected in
                XCTAssertEqual(context?.matches(selected), true); pastes += 1; apply(value)
                XCTAssertEqual(text, expected); return true
            }, normalizesCaseAfterDelimiter: { _ in true })
    }
    func apply(_ value: String) {
        let native = NSRange(location: range.location, length: range.length)
        replaced.append((text as NSString).substring(with: native)); inserted.append(value)
        text = (text as NSString).replacingCharacters(in: native, with: value)
        range = CFRange(location: native.location + value.utf16.count, length: 0)
    }
    func insertPhysical(_ value: String) {
        text = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: value)
        range = CFRange(location: range.location + value.utf16.count, length: 0)
    }
    func space() -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [32]); return event
    }
}
