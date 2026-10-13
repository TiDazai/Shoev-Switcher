import AppKit
import SwiftUI
import XCTest
@testable import ShoevSwitcher

final class ApplicationInterfaceTests: XCTestCase {
    func testMainWindowContainsSeparateJournalDiaryAndDictionary() {
        XCTAssertEqual(ApplicationPage.allCases.map(\.rawValue), ["Обзор", "Switcher", "Spell", "Журнал", "Дневник", "Словарь"])
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
        XCTAssertEqual(controller.window?.appearance?.name, .aqua)
        XCTAssertNotNil(controller.window?.contentView)
        controller.window?.close()
    }
    func testPlatinumAssetsAreBundledAndCached() {
        XCTAssertNotNil(Brand.surfaceImage)
        XCTAssertNotNil(Brand.catImage)
        XCTAssertTrue(Brand.surfaceImage === Brand.surfaceImage)
        XCTAssertGreaterThan(Brand.surfaceImage?.size.width ?? 0, 1000)
        XCTAssertGreaterThan(Brand.catImage?.size.height ?? 0, 500)
    }
    func testLightThemeTextContrast() {
        func luminance(_ color: SwiftUI.Color) -> Double {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        for text in [Brand.ink, Brand.accent, Brand.secondary, Brand.warning] {
            XCTAssertGreaterThanOrEqual((luminance(Brand.background) + 0.05) / (luminance(text) + 0.05), 4.5)
        }
        XCTAssertGreaterThanOrEqual(1.05 / (luminance(Brand.selection) + 0.05), 4.5)
    }
}
