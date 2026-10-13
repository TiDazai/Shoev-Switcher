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
        XCTAssertEqual(controller.window?.appearance?.name, .darkAqua)
        XCTAssertNotNil(controller.window?.contentView)
        controller.window?.close()
    }
    func testMetalAssetsAreBundledAndCached() {
        XCTAssertNotNil(Brand.surfaceImage)
        XCTAssertNotNil(Brand.catImage)
        XCTAssertTrue(Brand.surfaceImage === Brand.surfaceImage)
        XCTAssertGreaterThan(Brand.surfaceImage?.size.width ?? 0, 1000)
        XCTAssertGreaterThan(Brand.catImage?.size.height ?? 0, 500)
    }
    func testCatLogoHasNoOpaqueSquareBackground() throws {
        let image = try XCTUnwrap(Brand.catImage)
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertTrue(bitmap.hasAlpha)
        for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0), (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
            XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0, accuracy: 0.001)
        }
    }
    func testMetalThemeTextContrast() {
        func luminance(_ color: SwiftUI.Color) -> Double {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        func contrast(_ foreground: Color, _ background: Color) -> Double {
            let values = [luminance(foreground), luminance(background)]
            return (values.max()! + 0.05) / (values.min()! + 0.05)
        }
        for surface in [Brand.background, Brand.panel, Brand.panelHighlight, Brand.sidebar] {
            for text in [Brand.ink, Brand.accent, Brand.secondary, Brand.warning] {
                XCTAssertGreaterThanOrEqual(contrast(text, surface), 4.5)
            }
        }
        XCTAssertGreaterThanOrEqual(contrast(Brand.accent, Brand.selection), 4.5)
    }
}
