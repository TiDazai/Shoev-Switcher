import AppKit
import XCTest
@testable import ShoevSwitcher

private final class CapturedInjection: SpellTextInjecting {
    var calls: [(Int, String)] = []
    var succeeds = true
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?, context: CaretContext) -> Bool {
        calls.append((deleteCount, replacement))
        return succeeds
    }
}

final class SpellInputEngineTests: XCTestCase {
    func testCorrectionResumesAfterDeletion() {
        let suite = "SpellInputEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SpellPreferenceKey.enabled)
        defaults.set(true, forKey: SpellPreferenceKey.automaticCorrection)
        defaults.set(3, forKey: SpellPreferenceKey.minimumLength)
        defaults.set(250, forKey: SpellPreferenceKey.minimumScore)
        var prefix = ""
        let injector = CapturedInjection()
        let engine = SpellInputEngine(corrector: SpellCorrectionEngine(defaults: defaults), injector: injector,
            defaults: defaults, readCaret: { CaretContext(prefix: prefix, selectionLength: 0) },
            frontmost: { nil })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true)!
        event.flags = []
        let monitor = KeyboardMonitor()
        for _ in 0..<2 {
            for character in "превет" {
                XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(character), keyCode: 35))
                prefix.append(character)
            }
            XCTAssertTrue(engine.keyboardMonitor(monitor, keyDown: event, text: " ", keyCode: 49))
            XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: "", keyCode: 51))
            prefix = ""
        }
        XCTAssertEqual(injector.calls.count, 2)
    }

    func testIdenticalTextInDifferentFieldsDoesNotMatch() {
        let first = CaretContext(prefix: "превет", selectionLength: 0,
            element: AXUIElementCreateApplication(11))
        let second = CaretContext(prefix: "превет", selectionLength: 0,
            element: AXUIElementCreateApplication(12))
        XCTAssertTrue(first.matches(first))
        XCTAssertFalse(first.matches(second))
    }

    func testFailedCapitalizationPreservesOriginalKey() {
        let suite = "SpellInputEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SpellPreferenceKey.enabled)
        defaults.set(true, forKey: SpellPreferenceKey.automaticCapitalization)
        let injector = CapturedInjection()
        injector.succeeds = false
        var prefix = "Готово. "
        let engine = SpellInputEngine(injector: injector, defaults: defaults,
            readCaret: { CaretContext(prefix: prefix, selectionLength: 0) }, frontmost: { nil })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true)!
        event.flags = []
        let monitor = KeyboardMonitor()
        for c in "привет" {
            XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(c), keyCode: 35))
            prefix.append(c)
            XCTAssertTrue(injector.calls.isEmpty)
        }
        XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: " ", keyCode: 49))
        prefix += " "
        XCTAssertEqual(injector.calls.first?.1, "Привет")
        XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: "я", keyCode: 35))
        XCTAssertEqual(injector.calls.count, 1)
    }

    func testCapitalizationWaitsForWordBoundaryAfterSentenceMarks() {
        for preceding in ["", "Готово. ", "Готово! ", "Готово? ", "Готово… ", "Готово\n"] {
            let suite = "SpellInputEngineTests-\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: SpellPreferenceKey.enabled)
            defaults.set(true, forKey: SpellPreferenceKey.automaticCapitalization)
            var prefix = preceding
            let injector = CapturedInjection()
            let engine = SpellInputEngine(injector: injector, defaults: defaults,
                readCaret: { CaretContext(prefix: prefix, selectionLength: 0) }, frontmost: { nil })
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true)!
            event.flags = []
            let monitor = KeyboardMonitor()
            for c in "привет" {
                XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(c), keyCode: 35))
                prefix.append(c)
            }
            XCTAssertTrue(injector.calls.isEmpty, preceding)
            XCTAssertTrue(engine.keyboardMonitor(monitor, keyDown: event, text: " ", keyCode: 49), preceding)
            XCTAssertEqual(injector.calls.first?.1, "Привет", preceding)
        }
    }

    func testEnterAndTabNeverInvokeReplacement() {
        let suite = "SpellInputEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SpellPreferenceKey.enabled)
        defaults.set(true, forKey: SpellPreferenceKey.automaticCapitalization)
        defaults.set(true, forKey: SpellPreferenceKey.automaticCorrection)
        defaults.set(true, forKey: SpellPreferenceKey.automaticPunctuation)
        var prefix = ""
        let injector = CapturedInjection()
        let engine = SpellInputEngine(injector: injector, defaults: defaults,
            readCaret: { CaretContext(prefix: prefix, selectionLength: 0) }, frontmost: { nil })
        let monitor = KeyboardMonitor()
        for (code, text) in [(36, "\r"), (76, "\r"), (48, "\t"), (36, "\n")] {
            for flags: CGEventFlags in [[], .maskShift] {
                prefix = ""
                engine.keyboardMonitorDidResetInput(monitor)
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true)!
                event.flags = []
                for c in "превет" {
                    XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(c), keyCode: 35))
                    prefix.append(c)
                }
                event.flags = flags
                XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: text, keyCode: CGKeyCode(code)))
                XCTAssertEqual(event.flags, flags)
                XCTAssertTrue(injector.calls.isEmpty)
            }
        }
    }

    func testExternalLayoutReplacementDiscardsUnconvertedPhrase() {
        let suite = "SpellInputEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SpellPreferenceKey.enabled)
        defaults.set(true, forKey: SpellPreferenceKey.automaticCapitalization)
        var prefix = "Готово. "
        let injector = CapturedInjection()
        let engine = SpellInputEngine(injector: injector, defaults: defaults,
            readCaret: { CaretContext(prefix: prefix, selectionLength: 0) }, frontmost: { nil })
        let monitor = KeyboardMonitor()
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true)!
        event.flags = []
        for c in "ghbdtn" {
            XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(c), keyCode: 35))
            prefix.append(c)
        }
        // Switcher handles the delimiter first and consumes that event. Spell
        // next sees the changed field on the following physical letter.
        prefix = "Готово. привет "
        for c in "мир" {
            XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(c), keyCode: 35))
            prefix.append(c)
        }
        XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: " ", keyCode: 49))
        XCTAssertTrue(injector.calls.isEmpty)
    }

    func testIgnoredSetterIsNotConfusedWithChangedOrUnknownText() {
        XCTAssertTrue(TextReplacement.wasIgnored(before: "превет", expected: "привет ", after: "превет"))
        XCTAssertFalse(TextReplacement.wasIgnored(before: "превет", expected: "привет ", after: "привет "))
        XCTAssertFalse(TextReplacement.wasIgnored(before: "превет", expected: "привет ", after: nil))
        XCTAssertFalse(TextReplacement.wasIgnored(before: "привет", expected: "привет", after: "привет"))
    }

    func testFailedWordCorrectionPreservesDelimiter() {
        let suite = "SpellInputEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SpellPreferenceKey.enabled)
        defaults.set(true, forKey: SpellPreferenceKey.automaticCorrection)
        defaults.set(false, forKey: SpellPreferenceKey.automaticCapitalization)
        defaults.set(false, forKey: SpellPreferenceKey.automaticPunctuation)
        defaults.set(3, forKey: SpellPreferenceKey.minimumLength)
        defaults.set(250, forKey: SpellPreferenceKey.minimumScore)
        var prefix = ""
        let injector = CapturedInjection()
        injector.succeeds = false
        let engine = SpellInputEngine(corrector: SpellCorrectionEngine(defaults: defaults), injector: injector, defaults: defaults,
            readCaret: { CaretContext(prefix: prefix, selectionLength: 0) }, frontmost: { nil })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        event.flags = []
        let monitor = KeyboardMonitor()
        for character in "превет" {
            XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(character), keyCode: 0))
            prefix.append(character)
        }
        XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: " ", keyCode: 49))
        XCTAssertEqual(injector.calls.first?.1, "ивет")
    }

    func testUnavailableFieldNeverGetsCapitalizedOrPunctuated() {
        exercise(nil, input: "превет ", expectedCalls: 0)
    }

    func testSelectionIsNeverAutomaticallyCapitalized() {
        exercise(CaretContext(prefix: "", selectionLength: 6), input: "п", expectedCalls: 0)
    }

    func testEditingAtStartOfExistingWordPreservesCase() {
        exercise(CaretContext(prefix: "", selectionLength: 0, nextCharacter: "р"), input: "п", expectedCalls: 0)
    }

    private func exercise(_ caret: CaretContext?, input: String, expectedCalls: Int) {
        let suite = "SpellInputEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SpellPreferenceKey.enabled)
        defaults.set(true, forKey: SpellPreferenceKey.automaticCapitalization)
        defaults.set(true, forKey: SpellPreferenceKey.automaticPunctuation)
        let injector = CapturedInjection()
        let engine = SpellInputEngine(injector: injector, defaults: defaults, readCaret: { caret }, frontmost: { nil })
        let monitor = KeyboardMonitor()
        for c in input {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            event.flags = []
            XCTAssertFalse(engine.keyboardMonitor(monitor, keyDown: event, text: String(c), keyCode: 0))
        }
        XCTAssertEqual(injector.calls.count, expectedCalls)
    }
}
