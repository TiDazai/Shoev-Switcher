import ApplicationServices
import Foundation

struct SelectionConversion: Equatable {
    let original: String
    let replacement: String
    let sourceLanguage: InputLanguage
    let targetLanguage: InputLanguage
}

final class TextSelectionConverter {
    private let systemWideElement = AXUIElementCreateSystemWide()

    init() { AXUIElementSetMessagingTimeout(systemWideElement, 0.03) }

    func convertSelection(
        sourceLanguage: InputLanguage,
        sourceManager: InputSourceManaging,
        injector: TextReplacing
    ) -> SelectionConversion? {
        guard let element = focusedElement(), !isSecure(element),
              let selectedText = stringAttribute(element, key: kAXSelectedTextAttribute as CFString),
              !selectedText.isEmpty, selectedText.count <= 20_000 else { return nil }
        let detectedSource = Self.detectedLanguage(in: selectedText) ?? sourceLanguage
        let targetLanguage: InputLanguage = detectedSource == .english ? .russian : .english
        let replacement = sourceManager.convertedText(
            selectedText,
            from: detectedSource,
            to: targetLanguage
        )
        guard replacement != selectedText else { return nil }
        guard let before = TextReplacementContextReader().read(),
              CFEqual(before.element, element), before.range.length > 0,
              (before.text as NSString).substring(with: NSRange(location: before.range.location, length: before.range.length)) == selectedText,
              let current = TextReplacementContextReader().read(), before.matches(current) else { return nil }

        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        )
        guard status == .success else { return nil }
        let expectedText = (before.text as NSString).replacingCharacters(
            in: NSRange(location: before.range.location, length: before.range.length), with: replacement)
        guard let after = TextReplacementContextReader().read(), CFEqual(after.element, element), after.text == expectedText else { return nil }
        return SelectionConversion(
            original: selectedText,
            replacement: replacement,
            sourceLanguage: detectedSource,
            targetLanguage: targetLanguage
        )
    }

    static func detectedLanguage(in text: String) -> InputLanguage? {
        var latin = 0
        var cyrillic = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            switch scalar.value {
            case 0x0041...0x007A: latin += 1
            case 0x0400...0x052F: cyrillic += 1
            default: break
            }
        }
        guard latin != cyrillic else { return nil }
        return latin > cyrillic ? .english : .russian
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.03)
        return element
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        stringAttribute(element, key: kAXSubroleAttribute as CFString)
            == (kAXSecureTextFieldSubrole as String)
    }

    private func stringAttribute(_ element: AXUIElement, key: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value as? String
    }
}
