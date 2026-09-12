import AppKit
import XCTest
@testable import ShoevSwitcher

final class AccessibilityCaretLocatorTests: XCTestCase {
    func testConvertsQuartzCoordinatesUsingPrimaryScreenHeight() {
        XCTAssertEqual(
            AccessibilityCaretLocator.appKitPoint(
                fromQuartz: CGPoint(x: 420, y: 180),
                primaryScreenMaxY: 900
            ),
            NSPoint(x: 420, y: 720)
        )
    }

    func testConvertsPointOnDisplayAbovePrimaryScreen() {
        XCTAssertEqual(
            AccessibilityCaretLocator.appKitPoint(
                fromQuartz: CGPoint(x: 120, y: -300),
                primaryScreenMaxY: 900
            ),
            NSPoint(x: 120, y: 1200)
        )
    }
}
