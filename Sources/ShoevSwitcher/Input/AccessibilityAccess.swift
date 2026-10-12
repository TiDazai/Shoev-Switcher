import ApplicationServices

/// Injectable AX boundary. Tests never need to inspect or modify a real app.
struct AccessibilityAccess {
    var copy: (AXUIElement, String) -> CFTypeRef? = { element, name in
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    var parameter: (AXUIElement, String, CFTypeRef) -> CFTypeRef? = { element, name, argument in
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, argument, &value) == .success else { return nil }
        return value
    }
    var parameterNames: (AXUIElement) -> [String] = { element in
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
    var writable: (AXUIElement, String) -> Bool = { element, name in
        var result: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }
    var set: (AXUIElement, String, CFTypeRef) -> AXError = { element, name, value in
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }
}
