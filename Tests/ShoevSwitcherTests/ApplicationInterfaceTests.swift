import AppKit
import XCTest
@testable import ShoevSwitcher

final class ApplicationInterfaceTests: XCTestCase {
    func testMainWindowContainsFourIndependentSections() {
        XCTAssertEqual(ApplicationPage.allCases.map(\.rawValue), ["Обзор", "Switcher", "Spell", "Дневник"])
    }
    func testNativeMainWindowUsesTheProductName() {
        _ = NSApplication.shared
        let suite = "ApplicationInterfaceTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ApplicationModel(monitor: KeyboardMonitor(), sourceManager: InputSourceManager(defaults: defaults))
        let controller = ApplicationWindowController(model: model)
        XCTAssertEqual(controller.window?.title, "Shoev Switcher")
        XCTAssertEqual(controller.window?.minSize.width, 960)
        XCTAssertNotNil(controller.window?.contentView)
        controller.window?.close()
    }
}
