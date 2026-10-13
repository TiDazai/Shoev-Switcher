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
        let app = focusedApplication()
        var triedFocus: AXUIElement?
        // Rich editors can expose a wrapper as system-wide focus while their
        // own focused element is the actual editor. Do not special-case Word.
        if let app {
            let application = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(application, 0.03)
            if let focused = access.copy(application, kAXFocusedUIElementAttribute),
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = focused as! AXUIElement
                guard access.processID(element) == app.pid else { diagnostic(.contextChanged); return nil }
                triedFocus = element
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
        let element = focused as! AXUIElement
        if let app, access.processID(element) != app.pid { diagnostic(.contextChanged); return nil }
        if let triedFocus, CFEqual(triedFocus, element) { return nil }
        return read(focusedElement: element, deadline: deadline)
    }

    func read(focusedElement: AXUIElement, deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 0.075) -> CaretContext? {
        var element = focusedElement
        var failure = SpellInputDiagnostic.missingRange
        // Web editors may focus a child inside the editable field. Stay within
        // its nearest text-control ancestors; never search a whole document.
        for depth in 0..<8 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.03)
            if access.copy(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
                diagnostic(.secureField); return nil
            }
            let role = access.copy(element, kAXRoleAttribute) as? String
            let isTextControl = role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
            let editable = isTextControl || access.copy(element, "AXEditable") as? Bool == true
            let webArea = role == "AXWebArea"
            if depth == 0 || editable || webArea {
                if !webArea {
                    let rawRange = access.copy(element, kAXSelectedTextRangeAttribute)
                    let rangesValue = access.copy(element, kAXSelectedTextRangesAttribute)
                    let rawRanges = rangesValue as? [CFTypeRef]
                    if rangesValue != nil, rawRanges == nil { diagnostic(.invalidRange); return nil }
                    if let rawRanges, rawRanges.count > 1 { diagnostic(.multipleSelection); return nil }
                    var choices: [(CFTypeRef, TextSelectionTransport)] = []
                    if let rawRange { choices.append((rawRange, .range)) }
                    if let first = rawRanges?.first { choices.append((first, .ranges)) }
                    for (raw, transport) in choices {
                        guard CFGetTypeID(raw) == AXValueGetTypeID() else { failure = .invalidRange; continue }
                        var range = CFRange()
                        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { failure = .invalidRange; continue }
                        if let text = access.copy(element, kAXValueAttribute) as? String {
                            if var context = Self.context(element: element, text: text, range: range) {
                                context.selectionTransport = transport
                                return context
                            }
                            failure = .invalidRange
                        } else { failure = .missingValue }
                    }
                    // Some editors omit their caret range only while empty.
                    // An actually empty, writable text control has exactly one
                    // possible caret position. Never infer one in populated text.
                    if editable, rawRange == nil, rawRanges?.isEmpty != false,
                       access.copy(element, kAXValueAttribute) as? String == "",
                       (access.copy(element, "AXEditable") as? Bool == true
                        || access.writable(element, kAXValueAttribute)
                        || access.writable(element, kAXSelectedTextAttribute)),
                       access.copy(element, kAXSelectedTextMarkerRangeAttribute as String) == nil {
                        let transport: TextSelectionTransport = access.writable(element, kAXSelectedTextRangeAttribute) ? .range : .ranges
                        if access.writable(element, transport == .range ? kAXSelectedTextRangeAttribute : kAXSelectedTextRangesAttribute) {
                            var context = Self.context(element: element, text: "", range: CFRange(location: 0, length: 0))!
                            context.selectionTransport = transport
                            diagnostic(.emptyField)
                            return context
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
