import Foundation
import XCTest

final class PlatformRequirementsTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPackageAndBundleRequireMacOS26() throws {
        let package = try String(contentsOf: projectRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(".macOS(\"26.0\")"))
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "26.0")
    }

    func testWorkflowsRunOnMacOS26() throws {
        for filename in ["ci.yml", "tests.yml", "release.yml"] {
            let workflow = try String(contentsOf: projectRoot.appendingPathComponent(".github/workflows/\(filename)"), encoding: .utf8)
            XCTAssertTrue(workflow.contains("runs-on: macos-26"), filename)
            XCTAssertFalse(workflow.contains("runs-on: macos-15"), filename)
        }
    }
}
