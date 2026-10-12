import AppKit
import ApplicationServices
/// Immediate field verification; never persists or logs field text.
final class VerifiedCaretContextReader {
    private let access: AccessibilityAccess
    private let diagnostic: (SpellInputDiagnostic) -> Void

    init(access: AccessibilityAccess = AccessibilityAccess(),
         diagnostic: @escaping (SpellInputDiagnostic) -> Void = { SpellInputDiagnostics.shared.record($0) }) {
        self.access = access
        self.diagnostic = diagnostic
    }

    func read() -> CaretContext? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.03)
        guard let focused = access.copy(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { diagnostic(.missingFocus); return nil }
        return read(focusedElement: focused as! AXUIElement)
    }

    func read(focusedElement: AXUIElement) -> CaretContext? {
        var element = focusedElement
        var failure = SpellInputDiagnostic.missingRange
        let deadline = ProcessInfo.processInfo.systemUptime + 0.075
        // Web editors may focus a child inside the editable field. Stay within
        // its nearest text-control ancestors; never search a whole document.
        for depth in 0..<4 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.03)
            if access.copy(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
                diagnostic(.secureField); return nil
            }
            let role = access.copy(element, kAXRoleAttribute) as? String
            if depth == 0 || role == kAXTextFieldRole || role == kAXTextAreaRole {
                if let rawRange = access.copy(element, kAXSelectedTextRangeAttribute),
                   CFGetTypeID(rawRange) == AXValueGetTypeID() {
                    var range = CFRange()
                    if AXValueGetValue(rawRange as! AXValue, .cfRange, &range) {
                        guard let text = access.copy(element, kAXValueAttribute) as? String else {
                            diagnostic(.missingValue); return nil
                        }
                        guard let context = Self.context(element: element, text: text, range: range) else {
                            diagnostic(.invalidRange); return nil
                        }
                        return context
                    }
                    failure = .invalidRange
                }
            }
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let parent = access.copy(element, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID(), !CFEqual(parent, element) else { break }
            element = parent as! AXUIElement
        }
        diagnostic(failure)
        return nil
    }

    static func context(element: AXUIElement, text: String, range: CFRange) -> CaretContext? {
        let nsText = text as NSString
        guard range.location >= 0, range.length >= 0, range.location <= nsText.length,
              range.length <= nsText.length - range.location else { return nil }
        return CaretContext(
            prefix: nsText.substring(to: range.location),
            selectionLength: range.length,
            nextCharacter: nsText.substring(from: range.location + range.length).first,
            element: element,
            fullText: text
        )
    }
}
