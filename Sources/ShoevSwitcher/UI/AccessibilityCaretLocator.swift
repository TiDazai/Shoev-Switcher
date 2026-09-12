import AppKit
import ApplicationServices
import Foundation

final class AccessibilityCaretLocator {
    private let systemWideElement = AXUIElementCreateSystemWide()

    func caretLocation() -> NSPoint? {
        guard let element = focusedElement(), !isSecure(element), isEditable(element) else { return nil }
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success, let rangeValue else { return nil }

        let selectedRangeValue = unsafeBitCast(rangeValue, to: AXValue.self)
        var selectedRange = CFRange()
        guard AXValueGetValue(selectedRangeValue, .cfRange, &selectedRange),
              selectedRange.location != kCFNotFound,
              selectedRange.length >= 0 else { return nil }

        var caretRange = CFRange(location: selectedRange.location + selectedRange.length, length: 0)
        guard let caretRangeValue = AXValueCreate(.cfRange, &caretRange) else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            caretRangeValue,
            &boundsValue
        ) == .success, let boundsValue else { return nil }
        let axValue = unsafeBitCast(boundsValue, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect),
              rect.height > 0,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite else { return nil }
        return appKitPoint(fromQuartz: CGPoint(x: rect.maxX, y: rect.maxY))
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

    private func isEditable(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, key: kAXRoleAttribute as CFString)
        let subrole = stringAttribute(element, key: kAXSubroleAttribute as CFString)
        let editable = boolAttribute(element, key: "AXEditable" as CFString) == true
        var settable = DarwinBoolean(false)
        let canSetValue = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
        return TextInputAccessibilityTraits.isEditable(
            role: role,
            subrole: subrole,
            editableAttribute: editable,
            valueIsSettable: canSetValue
        )
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

    private func boolAttribute(_ element: AXUIElement, key: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value as? Bool
    }

    private func appKitPoint(fromQuartz point: CGPoint) -> NSPoint? {
        guard let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY else { return nil }
        let converted = Self.appKitPoint(fromQuartz: point, primaryScreenMaxY: primaryScreenMaxY)
        guard NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(converted) }) else {
            return nil
        }
        return converted
    }

    static func appKitPoint(fromQuartz point: CGPoint, primaryScreenMaxY: CGFloat) -> NSPoint {
        NSPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }
}
