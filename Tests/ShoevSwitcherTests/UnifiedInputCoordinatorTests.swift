import AppKit
import XCTest
@testable import ShoevSwitcher

final class UnifiedInputCoordinatorTests: XCTestCase {
    func testBothDisabledDoNotProcessTyping() { check(switcher: false, spell: false, expected: []) }
    func testSpellWorksWithoutSwitcher() { check(switcher: false, spell: true, expected: ["spell"]) }
    func testSwitcherWorksWithoutSpell() { check(switcher: true, spell: false, expected: ["switcher"]) }
    func testBothRunInDeterministicOrder() { check(switcher: true, spell: true, expected: ["switcher", "spell"]) }
    func testQueuedLayoutConversionPreventsCompetingSpellEdit() {
        check(switcher: true, spell: true, pending: true, expected: ["switcher"])
    }
    func testConsumedLayoutEventDoesNotReachSpell() {
        check(switcher: true, spell: true, consumed: true, expected: ["switcher"])
    }
    func testStandaloneSpellPausesOnlyIntegratedSpell() {
        check(switcher: true, spell: true, standalone: true, expected: ["switcher"])
    }
    func testOwnSettingsFieldsAreNeverChanged() {
        check(switcher: true, spell: true, ownWindow: true, expected: [])
    }
    func testNamespacedPreferencesDoNotChangeExistingSwitcher() {
        let suite = "UnifiedPreferencesTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: defaults)
        SpellPreferences.register(in: defaults)
        defaults.set(false, forKey: SpellPreferenceKey.enabled)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.enabled))
        defaults.set(false, forKey: PreferenceKey.enabled)
        defaults.set(true, forKey: SpellPreferenceKey.enabled)
        XCTAssertTrue(defaults.bool(forKey: SpellPreferenceKey.enabled))
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.enabled))
    }
    private func check(switcher: Bool, spell: Bool, pending: Bool = false, consumed: Bool = false,
                       standalone: Bool = false, ownWindow: Bool = false, expected: [String]) {
        let suite = "UnifiedCoordinatorTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(switcher, forKey: PreferenceKey.enabled)
        defaults.set(spell, forKey: SpellPreferenceKey.enabled)
        var calls: [String] = []
        let layout = RecordingDelegate { calls.append("switcher"); return consumed }
        let spelling = RecordingDelegate { calls.append("spell"); return false }
        let coordinator = UnifiedInputCoordinator(switcher: layout, spell: spelling, conversionPending: { pending },
            defaults: defaults, standaloneRunning: { standalone }, ownWindowFocused: { ownWindow })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        let result = coordinator.keyboardMonitor(KeyboardMonitor(), keyDown: event, text: " ", keyCode: 49)
        XCTAssertEqual(result, consumed && switcher && !ownWindow)
        XCTAssertEqual(calls, expected)
    }
}
private final class RecordingDelegate: KeyboardMonitorDelegate {
    private let handle: () -> Bool
    init(_ handle: @escaping () -> Bool) { self.handle = handle }
    func keyboardMonitorDidResetInput(_ monitor: KeyboardMonitor) {}
    func keyboardMonitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool { handle() }
    func keyboardMonitor(_ monitor: KeyboardMonitor, flagsChanged event: CGEvent, keyCode: CGKeyCode) {}
}
