import AppKit
import ApplicationServices

struct TextReplacementContext {
    let element: AXUIElement
    let text: String
    let range: CFRange

    var prefix: String { (text as NSString).substring(to: range.location) }

    var startsInsideWord: Bool {
        let suffix = (text as NSString).substring(from: range.location + range.length)
        return [prefix.last, suffix.first].contains { character in
            guard let character else { return false }
            return character.isLetter || character.isNumber || "@#/_\\-'’".contains(character)
        }
    }

    func matches(_ other: TextReplacementContext) -> Bool {
        CFEqual(element, other.element) && text == other.text
            && range.location == other.range.location && range.length == other.range.length
    }

    static func replacementRange(in text: String, caret: Int, original: String) -> CFRange? {
        let value = text as NSString
        let length = original.utf16.count
        guard !original.isEmpty, caret >= length, caret <= value.length else { return nil }
        let range = NSRange(location: caret - length, length: length)
        guard value.substring(with: range) == original else { return nil }
        return CFRange(location: range.location, length: range.length)
    }
}

final class TextReplacementContextReader {
    func read() -> TextReplacementContext? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.03)
        var subrole: CFTypeRef?
        let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard (subroleStatus == .success || subroleStatus == .attributeUnsupported),
              subrole as? String != kAXSecureTextFieldSubrole as String else { return nil }
        var rawRange: CFTypeRef?
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rawRange) == .success,
              let rawRange, CFGetTypeID(rawRange) == AXValueGetTypeID(),
              AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range),
              range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location else { return nil }
        return TextReplacementContext(element: element, text: text, range: range)
    }
}
