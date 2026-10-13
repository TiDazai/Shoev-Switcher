import AppKit
import ApplicationServices

struct TextReplacementContext {
    let element: AXUIElement
    let text: String
    let range: CFRange
    var textOffset: Int = 0
    var selectionTransport: TextSelectionTransport = .range

    var prefix: String { (text as NSString).substring(to: range.location) }

    var startsInsideWord: Bool {
        let suffix = (text as NSString).substring(from: range.location + range.length)
        return [prefix.last, suffix.first].contains { character in
            guard let character else { return false }
            return character.isLetter || character.isNumber || "@#/_\\-'’".contains(character)
        }
    }

    func matches(_ other: TextReplacementContext) -> Bool {
        sameRegion(as: other) && text == other.text
            && range.location == other.range.location && range.length == other.range.length
    }

    func sameRegion(as other: TextReplacementContext) -> Bool {
        CFEqual(element, other.element) && textOffset == other.textOffset
            && selectionTransport == other.selectionTransport
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
        guard let context = VerifiedCaretContextReader().read(),
              let element = context.element, let text = context.fullText else { return nil }
        return TextReplacementContext(element: element, text: text,
            range: CFRange(location: context.prefix.utf16.count, length: context.selectionLength),
            textOffset: context.textOffset, selectionTransport: context.selectionTransport)
    }
}
