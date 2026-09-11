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

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success, let boundsValue else { return nil }
        let axValue = unsafeBitCast(boundsValue, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
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
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let quartzFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard quartzFrame.contains(point) else { continue }
            return NSPoint(
                x: screen.frame.minX + point.x - quartzFrame.minX,
                y: screen.frame.maxY - (point.y - quartzFrame.minY)
            )
        }
        return nil
    }
}
