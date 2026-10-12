import AppKit

/// One keyboard tap, deterministic priority: layout before spelling.
final class UnifiedInputCoordinator: KeyboardMonitorDelegate {
    private let switcher: KeyboardMonitorDelegate
    private let spell: KeyboardMonitorDelegate
    private let conversionPending: () -> Bool
    private let defaults: UserDefaults
    private let standaloneRunning: () -> Bool
    private let ownWindowFocused: () -> Bool

    init(switcher: KeyboardMonitorDelegate, spell: KeyboardMonitorDelegate,
         conversionPending: @escaping () -> Bool, defaults: UserDefaults = .standard,
         standaloneRunning: @escaping () -> Bool = {
             !NSRunningApplication.runningApplications(withBundleIdentifier: "com.shoev.spell").isEmpty
         },
         ownWindowFocused: @escaping () -> Bool = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
         }) {
        self.switcher = switcher
        self.spell = spell
        self.conversionPending = conversionPending
        self.defaults = defaults
        self.standaloneRunning = standaloneRunning
        self.ownWindowFocused = ownWindowFocused
    }
    func keyboardMonitorDidResetInput(_ monitor: KeyboardMonitor) {
        switcher.keyboardMonitorDidResetInput(monitor)
        spell.keyboardMonitorDidResetInput(monitor)
    }
    func keyboardMonitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool {
        guard !ownWindowFocused() else { keyboardMonitorDidResetInput(monitor); return false }
        let switchingEnabled = defaults.bool(forKey: PreferenceKey.enabled)
        let consumed: Bool
        if switchingEnabled {
            consumed = switcher.keyboardMonitor(monitor, keyDown: event, text: text, keyCode: keyCode)
        } else {
            switcher.keyboardMonitorDidResetInput(monitor)
            consumed = false
        }
        guard !consumed, !(switchingEnabled && conversionPending()) else {
            spell.keyboardMonitorDidResetInput(monitor)
            return consumed
        }
        guard defaults.bool(forKey: SpellPreferenceKey.enabled), !standaloneRunning() else {
            spell.keyboardMonitorDidResetInput(monitor)
            return false
        }
        return spell.keyboardMonitor(monitor, keyDown: event, text: text, keyCode: keyCode)
    }
    func keyboardMonitor(_ monitor: KeyboardMonitor, flagsChanged event: CGEvent, keyCode: CGKeyCode) {
        guard !ownWindowFocused(), defaults.bool(forKey: PreferenceKey.enabled) else { return }
        switcher.keyboardMonitor(monitor, flagsChanged: event, keyCode: keyCode)
    }
}
