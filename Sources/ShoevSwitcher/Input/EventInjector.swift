import AppKit
import Carbon.HIToolbox
import Foundation

protocol TextReplacing {
    func replace(original: String, with replacement: String, trailingEvent: CGEvent?, context: TextReplacementContext) -> Bool
}

final class EventInjector: TextReplacing {
    static let syntheticEventMarker: Int64 = 0x53484F4556

    @discardableResult
    func replace(original: String, with replacement: String, trailingEvent: CGEvent? = nil, context: TextReplacementContext) -> Bool {
        guard !IsSecureEventInputEnabled(),
              context.range.length == 0,
              var range = TextReplacementContext.replacementRange(in: context.text, caret: context.range.location, original: original),
              let selectedRange = AXValueCreate(.cfRange, &range) else { return false }
        for attribute in [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute] {
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(context.element, attribute as CFString, &settable) == .success,
                  settable.boolValue else { return false }
        }
        let copied = trailingEvent?.copy()
        guard trailingEvent == nil || copied != nil,
              let current = TextReplacementContextReader().read(), current.matches(context) else { return false }
        guard AXUIElementSetAttributeValue(context.element, kAXSelectedTextRangeAttribute as CFString, selectedRange) == .success else { return false }
        let selected = TextReplacementContextReader().read()
        let delimiter = trailingEvent.flatMap(Self.inlineDelimiter)
        let insertedText = replacement + (delimiter ?? "")
        guard let selected, CFEqual(selected.element, context.element), selected.text == context.text,
              selected.range.location == range.location, selected.range.length == range.length,
              AXUIElementSetAttributeValue(context.element, kAXSelectedTextAttribute as CFString, insertedText as CFString) == .success else {
            var previous = context.range
            if let value = AXValueCreate(.cfRange, &previous) {
                AXUIElementSetAttributeValue(context.element, kAXSelectedTextRangeAttribute as CFString, value)
            }
            return false
        }
        let expectedText = (context.text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: insertedText)
        guard let after = TextReplacementContextReader().read(), CFEqual(after.element, context.element),
              after.text == expectedText else { return true }
        var end = CFRange(location: range.location + insertedText.utf16.count, length: 0)
        guard let value = AXValueCreate(.cfRange, &end),
              AXUIElementSetAttributeValue(context.element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return true }
        if delimiter == nil, let copied,
           let final = TextReplacementContextReader().read(), CFEqual(final.element, context.element),
           final.text == expectedText, final.range.location == end.location, final.range.length == 0 {
            copied.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            copied.post(tap: .cgAnnotatedSessionEventTap)
        }
        return true
    }

    static func inlineDelimiter(_ event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0, length <= buffer.count else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }
            ? text : nil
    }
}
