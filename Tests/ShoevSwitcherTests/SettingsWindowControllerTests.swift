import AppKit
import XCTest
@testable import ShoevSwitcher

final class SettingsWindowControllerTests: XCTestCase {
    func testDetailedSettingsBuildsAllFourSections() {
        _ = NSApplication.shared
        let controller = SettingsWindowController(
            monitor: KeyboardMonitor(),
            sourceManager: InputSourceManager(),
            onSaved: {}
        )
        let tabView = controller.window?.contentView.flatMap(findTabView)
        XCTAssertEqual(tabView?.numberOfTabViewItems, 4)
        XCTAssertEqual(
            tabView?.tabViewItems.map(\.label),
            ["Поведение", "Интерфейс и обучение", "Раскладки", "Дневник и исключения"]
        )
    }

    private func findTabView(in view: NSView) -> NSTabView? {
        if let tabView = view as? NSTabView { return tabView }
        return view.subviews.lazy.compactMap(findTabView).first
    }
}
