import AppKit
import ApplicationServices
import Foundation

final class TextInputHoverIndicator {
    private let sourceManager: InputSourceManager
    private let defaults: UserDefaults
    private let systemWideElement = AXUIElementCreateSystemWide()
    private let caretLocator = AccessibilityCaretLocator()
    private let panel: NSPanel
    private let flagLabel = NSTextField(labelWithString: "")

    private var pendingEvaluation: DispatchWorkItem?
    private var latestQuartzPoint = CGPoint.zero
    private var lastEvaluation = Date.distantPast
    private var hideWork: DispatchWorkItem?
    private var positionedAtCaret = false

    init(sourceManager: InputSourceManager, defaults: UserDefaults = .standard) {
        self.sourceManager = sourceManager
        self.defaults = defaults
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 28, height: 22),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    func mouseMoved(to quartzPoint: CGPoint) {
        latestQuartzPoint = quartzPoint
        if panel.isVisible, !positionedAtCaret {
            positionPanel(near: NSEvent.mouseLocation)
        }
        let elapsed = Date().timeIntervalSince(lastEvaluation)
        if elapsed >= evaluationInterval {
            pendingEvaluation?.cancel()
            pendingEvaluation = nil
            evaluateLatestPosition()
            return
        }

        guard pendingEvaluation == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingEvaluation = nil
            self?.evaluateLatestPosition()
        }
        pendingEvaluation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + evaluationInterval - elapsed, execute: work)
    }

    func inputActivityOccurred() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self,
                  self.defaults.bool(forKey: PreferenceKey.enabled),
                  self.defaults.bool(forKey: PreferenceKey.hoverLanguageIndicator),
                  let language = self.sourceManager.currentLanguage(),
                  let caret = self.caretLocator.caretLocation() else { return }
            self.show(language: language, near: caret, atCaret: true)
        }
    }

    func preferenceDidChange() {
        if !defaults.bool(forKey: PreferenceKey.hoverLanguageIndicator) {
            hide()
        } else {
            evaluateLatestPosition()
        }
    }

    func stop() {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        hide()
    }

    private func evaluateLatestPosition() {
        lastEvaluation = Date()
        guard defaults.bool(forKey: PreferenceKey.enabled),
              defaults.bool(forKey: PreferenceKey.hoverLanguageIndicator),
              let element = element(at: latestQuartzPoint),
              let processIdentifier = processIdentifier(of: element),
              !isExcluded(processIdentifier: processIdentifier),
              isEditableTextElement(element),
              let language = sourceManager.currentLanguage() else {
            hide()
            return
        }

        let caret = caretLocator.caretLocation()
        show(
            language: language,
            near: caret ?? NSEvent.mouseLocation,
            atCaret: caret != nil
        )
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &element
        ) == .success else { return nil }
        return element
    }

    private func isEditableTextElement(_ startingElement: AXUIElement) -> Bool {
        var element: AXUIElement? = startingElement
        for _ in 0..<6 {
            guard let current = element else { return false }
            let role = stringAttribute(current, key: kAXRoleAttribute as CFString)
            let subrole = stringAttribute(current, key: kAXSubroleAttribute as CFString)
            if subrole == (kAXSecureTextFieldSubrole as String) { return false }

            let editable = boolAttribute(current, key: "AXEditable" as CFString) == true
            var valueIsSettable = DarwinBoolean(false)
            let canSetValue = AXUIElementIsAttributeSettable(
                current,
                kAXValueAttribute as CFString,
                &valueIsSettable
            ) == .success && valueIsSettable.boolValue

            if TextInputAccessibilityTraits.isEditable(
                role: role,
                subrole: subrole,
                editableAttribute: editable,
                valueIsSettable: canSetValue
            ) {
                return true
            }
            element = elementAttribute(current, key: kAXParentAttribute as CFString)
        }
        return false
    }

    private func processIdentifier(of element: AXUIElement) -> pid_t? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success else { return nil }
        return processIdentifier
    }

    private func isExcluded(processIdentifier: pid_t) -> Bool {
        guard let bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier else {
            return false
        }
        let exclusions = defaults.stringArray(forKey: PreferenceKey.excludedApplications) ?? []
        return exclusions.contains(bundleIdentifier)
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

    private func elementAttribute(_ element: AXUIElement, key: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.animationBehavior = .none

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        flagLabel.frame = content.bounds
        flagLabel.autoresizingMask = [.width, .height]
        flagLabel.alignment = .center
        flagLabel.font = .systemFont(ofSize: 16)
        content.addSubview(flagLabel)
        panel.contentView = content
    }

    private func positionPanel(near mouseLocation: NSPoint) {
        let size = panel.frame.size
        var origin = NSPoint(x: mouseLocation.x + 9, y: mouseLocation.y - 13)
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    private func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel.orderOut(nil)
    }

    private func show(language: InputLanguage, near point: NSPoint, atCaret: Bool) {
        positionedAtCaret = atCaret
        flagLabel.stringValue = language.flag
        positionPanel(near: point)
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private let evaluationInterval: TimeInterval = 0.10
}

enum TextInputAccessibilityTraits {
    static func isEditable(
        role: String?,
        subrole: String?,
        editableAttribute: Bool,
        valueIsSettable: Bool
    ) -> Bool {
        if subrole == (kAXSecureTextFieldSubrole as String) { return false }
        if editableAttribute { return true }
        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]
        return role.map(editableRoles.contains) == true && valueIsSettable
    }
}

private extension InputLanguage {
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .russian: return "🇷🇺"
        }
    }
}
