import ApplicationServices
import Foundation

final class SensitiveInputGuard {
    private var cachedProcessIdentifier: pid_t?
    private var cachedResult = false
    private var cacheDate = Date.distantPast

    func isSensitive(processIdentifier: pid_t?) -> Bool {
        guard let processIdentifier else { return false }
        let now = Date()
        if cachedProcessIdentifier == processIdentifier,
           now.timeIntervalSince(cacheDate) < 0.2 {
            return cachedResult
        }

        let result = focusedElementIsSecure(processIdentifier: processIdentifier)
        cachedProcessIdentifier = processIdentifier
        cachedResult = result
        cacheDate = now
        return result
    }

    func reset() {
        cachedProcessIdentifier = nil
        cachedResult = false
        cacheDate = .distantPast
    }

    private func focusedElementIsSecure(processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else { return false }

        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSubroleAttribute as CFString,
            &subroleValue
        ) == .success else { return false }
        return (subroleValue as? String) == (kAXSecureTextFieldSubrole as String)
    }
}
