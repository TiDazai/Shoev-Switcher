import AppKit
import ApplicationServices
import XCTest
@testable import ShoevSwitcher

final class InputEngineTests: XCTestCase {
    func testEnterAndTabRemainPhysicalEditorActions() {
        for (code, text) in [(36, "\r"), (76, "\r"), (48, "\t"), (36, "\n")] {
            for flags: CGEventFlags in [[], .maskShift] {
                let fixture = Fixture()
                fixture.type("ghbdtn")
                XCTAssertFalse(fixture.key(text, code: CGKeyCode(code), flags: flags))
                XCTAssertEqual(fixture.injector.calls, 0)
                XCTAssertTrue(fixture.source.selections.isEmpty)
                fixture.text = ""
                fixture.type("ghbdtn")
                XCTAssertTrue(fixture.key(" ", code: 49))
                XCTAssertEqual(fixture.text, "привет ")
            }
        }
    }

    func testPeriodCorrectionDoesNotBlockFollowingLetters() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        XCTAssertTrue(fixture.key(".", code: 47))
        XCTAssertEqual(fixture.text, "привет.")
        XCTAssertFalse(fixture.key("\r", code: 36))
        fixture.text = ""
        fixture.source.language = .english
        fixture.type("ghbdtn")
        XCTAssertTrue(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.text, "привет ")
    }

    func testIgnoredSetterIsNotConfusedWithChangedOrUnknownText() {
        XCTAssertTrue(EventInjector.wasIgnored(before: "ghbdtn", expected: "привет ", after: "ghbdtn"))
        XCTAssertFalse(EventInjector.wasIgnored(before: "ghbdtn", expected: "привет ", after: "привет "))
        XCTAssertFalse(EventInjector.wasIgnored(before: "ghbdtn", expected: "привет ", after: nil))
        XCTAssertFalse(EventInjector.wasIgnored(before: "привет", expected: "привет", after: "привет"))
    }
    func testCorrectionUndoAndNextCorrection() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        XCTAssertTrue(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.text, "привет ")
        XCTAssertTrue(fixture.key("", code: 51))
        XCTAssertEqual(fixture.text, "ghbdtn ")
        fixture.type("ghbdtn")
        XCTAssertTrue(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.text, "ghbdtn привет ")
    }

    func testFailedReplacementKeepsDelimiterAndLayout() {
        let fixture = Fixture()
        fixture.injector.succeeds = false
        fixture.type("ghbdtn")
        XCTAssertFalse(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.text, "ghbdtn ")
        XCTAssertEqual(fixture.source.selections, [])
    }

    func testChangedFieldWithSameTextIsNeverReplaced() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        fixture.field = AXUIElementCreateApplication(102)
        XCTAssertFalse(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.injector.calls, 0)
    }

    func testUndoDoesNotTouchAnotherField() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        XCTAssertTrue(fixture.key(" ", code: 49))
        fixture.field = AXUIElementCreateApplication(102)
        XCTAssertFalse(fixture.key("", code: 51))
        XCTAssertEqual(fixture.injector.calls, 1)
    }
    func testIdenticalWordInAnotherParagraphIsNotCorrected() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        fixture.offset = 1000
        XCTAssertFalse(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.injector.calls, 0)
    }

    func testUndoNeverTouchesAnIdenticalWordInAnotherParagraph() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        XCTAssertTrue(fixture.key(" ", code: 49))
        fixture.offset = 1000
        XCTAssertFalse(fixture.key("", code: 51))
        XCTAssertEqual(fixture.injector.calls, 1)
    }

    func testEditingPrefixInvalidatesToken() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        fixture.text = "changed ghbdtn"
        XCTAssertFalse(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.injector.calls, 0)
    }

    func testBackspaceResetsAndNextWordStillWorks() {
        let fixture = Fixture()
        fixture.type("ghbdt")
        XCTAssertFalse(fixture.key("", code: 51))
        fixture.text.removeLast()
        fixture.type(" ")
        fixture.type("ghbdtn")
        XCTAssertTrue(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.text, "ghbd привет ")
    }

    func testMissingContextAndInsideWordAreSkipped() {
        let fixture = Fixture()
        fixture.contextAvailable = false
        fixture.type("ghbdtn ")
        XCTAssertEqual(fixture.injector.calls, 0)
        fixture.contextAvailable = true
        fixture.text = "prefix"
        fixture.type("ghbdtn ")
        XCTAssertEqual(fixture.injector.calls, 0)
    }

    func testMonitorResetDiscardsStaleToken() {
        let fixture = Fixture()
        fixture.type("ghbdtn")
        fixture.engine.keyboardMonitorDidResetInput(fixture.monitor)
        XCTAssertFalse(fixture.key(" ", code: 49))
        XCTAssertEqual(fixture.injector.calls, 0)
    }

    func testShiftUsedForTypingIsNotManualDoubleTap() {
        let fixture = Fixture()
        for _ in 0..<2 {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 60, keyDown: true)!
            down.flags = .maskShift
            fixture.engine.keyboardMonitor(fixture.monitor, flagsChanged: down, keyCode: 60)
            fixture.type("g")
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 60, keyDown: false)!
            fixture.engine.keyboardMonitor(fixture.monitor, flagsChanged: up, keyCode: 60)
        }
        XCTAssertEqual(fixture.injector.calls, 0)
    }

    func testDelimiterClassificationPreservesKeyboardActions() {
        func event(_ text: String) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
            let units = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            return event
        }
        XCTAssertEqual(EventInjector.inlineDelimiter(event(" ")), " ")
        XCTAssertEqual(EventInjector.inlineDelimiter(event("!")), "!")
        XCTAssertEqual(EventInjector.inlineDelimiter(event("🐈")), "🐈")
        XCTAssertNil(EventInjector.inlineDelimiter(event("\n")))
        XCTAssertNil(EventInjector.inlineDelimiter(event("\t")))
    }

    func testReplacementRangeUsesUTF16AndExactSuffix() {
        XCTAssertEqual(TextReplacementContext.replacementRange(in: "🐈 ghbdtn", caret: 9, original: "ghbdtn")?.location, 3)
        XCTAssertNil(TextReplacementContext.replacementRange(in: "привет", caret: 6, original: "ghbdtn"))
        XCTAssertNil(TextReplacementContext.replacementRange(in: "abc", caret: 4, original: "abc"))
        XCTAssertNil(TextReplacementContext.replacementRange(in: "abc", caret: -1, original: "a"))
    }
}

private final class Fixture {
    var text = ""
    var field = AXUIElementCreateApplication(101)
    var contextAvailable = true
    var offset = 0
    let source = FakeSource()
    let injector = FakeInjector()
    let monitor = KeyboardMonitor()
    var engine: InputEngine!
    let defaults: UserDefaults
    let suite = "ShoevEngineTests-" + UUID().uuidString

    init() {
        defaults = UserDefaults(suiteName: suite)!
        Preferences.registerDefaults(in: defaults)
        defaults.set(false, forKey: PreferenceKey.applicationContext)
        defaults.set(false, forKey: PreferenceKey.correctionNotifications)
        let rules = RuleStore()
        engine = InputEngine(sourceManager: source,
            detector: LanguageDetector(rules: rules) { word, language in language == .russian && word == "привет" },
            ruleStore: rules, journalStore: nil, injector: injector, defaults: defaults,
            correctionNotifier: CorrectionNotifier(defaults: defaults),
            readContext: { [weak self] in
                guard let self, self.contextAvailable else { return nil }
                return TextReplacementContext(element: self.field, text: self.text,
                    range: CFRange(location: self.text.utf16.count, length: 0), textOffset: self.offset)
            }, frontmost: { nil })
        injector.apply = { [weak self] original, replacement, event in
            guard let self else { return }
            self.text = String(self.text.dropLast(original.count)) + replacement
            if let event, let delimiter = EventInjector.inlineDelimiter(event) { self.text += delimiter }
        }
    }
    deinit { defaults.removePersistentDomain(forName: suite) }
    func type(_ text: String) { for char in text { _ = key(String(char), code: char == " " ? 49 : 0) } }
    @discardableResult func key(_ text: String, code: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.flags = flags
        let units = Array(text.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        let suppressed = engine.keyboardMonitor(monitor, keyDown: event, text: text, keyCode: code)
        if !suppressed { self.text += text }
        return suppressed
    }
}

private final class FakeSource: InputSourceManaging {
    var language = InputLanguage.english
    var selections: [InputLanguage] = []
    func currentLanguage() -> InputLanguage? { language }
    func select(_ language: InputLanguage) -> Bool { self.language = language; selections.append(language); return true }
    func text(for strokes: [KeyStroke], in language: InputLanguage) -> String? {
        let value = strokes.map(\.visibleText).joined()
        return language == .russian && value == "ghbdtn" ? "привет" : value
    }
    func isPotentialWordStroke(_ stroke: KeyStroke) -> Bool { false }
    func convertedText(_ text: String, from: InputLanguage, to: InputLanguage) -> String { text }
}

private final class FakeInjector: TextReplacing {
    var succeeds = true
    var calls = 0
    var apply: ((String, String, CGEvent?) -> Void)?
    func replace(original: String, with replacement: String, trailingEvent: CGEvent?, context: TextReplacementContext) -> Bool {
        calls += 1
        guard succeeds else { return false }
        apply?(original, replacement, trailingEvent)
        return true
    }
}
