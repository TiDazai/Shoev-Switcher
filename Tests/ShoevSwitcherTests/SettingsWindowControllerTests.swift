import AppKit
import XCTest
@testable import ShoevSwitcher

final class SettingsWindowControllerTests: XCTestCase {
    func testDetailedSettingsBuildsAllThreeSections() {
        _ = NSApplication.shared
        let controller = SettingsWindowController(
            monitor: KeyboardMonitor(),
            sourceManager: InputSourceManager(),
            onSaved: {}
        )
        let tabView = controller.window?.contentView.flatMap(findTabView)
        XCTAssertEqual(tabView?.numberOfTabViewItems, 3)
        XCTAssertEqual(tabView?.tabViewItems.map(\.label), ["Поведение", "Раскладки", "Дневник и исключения"])
    }

    private func findTabView(in view: NSView) -> NSTabView? {
        if let tabView = view as? NSTabView { return tabView }
        return view.subviews.lazy.compactMap(findTabView).first
    }
}
