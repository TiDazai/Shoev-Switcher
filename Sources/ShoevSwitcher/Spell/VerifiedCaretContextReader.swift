import AppKit
import ApplicationServices
import OSLog
/// Immediate field verification; never persists or logs field text.
final class VerifiedCaretContextReader {
    private static var lastWordDiagnostic = Date.distantPast
    private let access: AccessibilityAccess
    private let diagnostic: (SpellInputDiagnostic) -> Void
    private let focusedApplication: () -> (pid: pid_t, bundle: String?)?

    init(access: AccessibilityAccess = AccessibilityAccess(),
         diagnostic: @escaping (SpellInputDiagnostic) -> Void = { SpellInputDiagnostics.shared.record($0) },
         focusedApplication: @escaping () -> (pid: pid_t, bundle: String?)? = {
             NSWorkspace.shared.frontmostApplication.map { ($0.processIdentifier, $0.bundleIdentifier) }
         }) {
        self.access = access
        self.diagnostic = diagnostic
        self.focusedApplication = focusedApplication
    }

    func read() -> CaretContext? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.075
        // Office's system-wide focus can point at a layout container while the
        // application's focus points at the actual page text control.
        if let app = focusedApplication(), app.bundle == "com.microsoft.Word" {
            let application = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(application, 0.03)
            if let focused = access.copy(application, kAXFocusedUIElementAttribute),
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = focused as! AXUIElement
                if access.copy(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
                    diagnostic(.secureField); return nil
                }
                if let context = read(focusedElement: element, deadline: deadline) { return context }
            }
        }
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.03)
        guard let focused = access.copy(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { diagnostic(.missingFocus); return nil }
        return read(focusedElement: focused as! AXUIElement, deadline: deadline)
    }

    func read(focusedElement: AXUIElement, deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 0.075) -> CaretContext? {
        var element = focusedElement
        var failure = SpellInputDiagnostic.missingRange
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
                        if let text = access.copy(element, kAXValueAttribute) as? String {
                            if let context = Self.context(element: element, text: text, range: range) { return context }
                            failure = .invalidRange
                        } else {
                            failure = .missingValue
                        }
                    }
                }
                if ProcessInfo.processInfo.systemUptime < deadline,
                   let context = AccessibilityTextSelection(access: access, deadline: deadline).readMarkerContext(in: element) {
                    diagnostic(.markerContext)
                    return context
                }
            }
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let parent = access.copy(element, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID(), !CFEqual(parent, element) else { break }
            element = parent as! AXUIElement
        }
        recordWordCapabilities(focusedElement)
        diagnostic(failure)
        return nil
    }

    /// Capability names/booleans only; never log document contents or markers.
    private func recordWordCapabilities(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.microsoft.Word",
              Date().timeIntervalSince(Self.lastWordDiagnostic) >= 10 else { return }
        Self.lastWordDiagnostic = Date()
        let range = access.copy(element, kAXSelectedTextRangeAttribute) != nil
        let markers = access.copy(element, kAXSelectedTextMarkerRangeAttribute as String) != nil
        let ranges = access.copy(element, kAXSelectedTextRangesAttribute) != nil
        let value = access.copy(element, kAXValueAttribute) != nil
        let names = access.parameterNames(element).filter { $0.hasPrefix("AX") }.sorted().joined(separator: ",")
        Logger(subsystem: "com.shoev.spell", category: "compatibility").info("Word text capabilities: range=\(range) markers=\(markers) ranges=\(ranges) value=\(value) parameters=\(names, privacy: .public)")
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
