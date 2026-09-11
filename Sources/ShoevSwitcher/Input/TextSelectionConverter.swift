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

    func convertSelection(
        sourceLanguage: InputLanguage,
        sourceManager: InputSourceManager,
        injector: EventInjector
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

        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        )
        if status != .success {
            injector.insert(replacement)
        }
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
        return unsafeBitCast(value, to: AXUIElement.self)
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
