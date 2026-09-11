import AppKit
import Foundation

final class CorrectionNotifier {
    private let defaults: UserDefaults
    private let caretLocator = AccessibilityCaretLocator()
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    func show(original: String, replacement: String) {
        guard defaults.bool(forKey: PreferenceKey.correctionNotifications) else { return }
        let summary = "\(abbreviate(original)) → \(abbreviate(replacement))"
        label.stringValue = summary
        let width = min(max(label.intrinsicContentSize.width + 22, 90), 380)
        panel.setContentSize(NSSize(width: width, height: 30))
        label.frame = panel.contentView?.bounds ?? .zero
        position(near: caretLocator.caretLocation() ?? NSEvent.mouseLocation)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.animationBehavior = .none

        let background = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        label.frame = background.bounds
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        background.addSubview(label)
        panel.contentView = background
    }

    private func position(near point: NSPoint) {
        let size = panel.frame.size
        var origin = NSPoint(x: point.x + 6, y: point.y - size.height - 8)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    private func abbreviate(_ value: String) -> String {
        value.count > 24 ? String(value.prefix(23)) + "…" : value
    }
}
