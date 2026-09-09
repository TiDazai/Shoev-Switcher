import CoreGraphics
import Foundation

final class EventInjector {
    static let syntheticEventMarker: Int64 = 0x53484F4556

    private let source = CGEventSource(stateID: .combinedSessionState)

    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent? = nil) {
        guard deleteCount >= 0 else { return }
        for _ in 0..<deleteCount {
            postKey(keyCode: 51, keyDown: true)
            postKey(keyCode: 51, keyDown: false)
        }
        postText(replacement)
        if let trailingEvent, let copied = trailingEvent.copy() {
            copied.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            copied.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func postKey(keyCode: CGKeyCode, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func postText(_ text: String) {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return }
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else {
                continue
            }
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            units.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress!)
            }
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
