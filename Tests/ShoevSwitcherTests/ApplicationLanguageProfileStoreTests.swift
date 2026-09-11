import XCTest
@testable import ShoevSwitcher

final class ApplicationLanguageProfileStoreTests: XCTestCase {
    func testLearnsDominantLanguageAfterThreeWords() {
        let suiteName = "ApplicationLanguageProfileStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ApplicationLanguageProfileStore(defaults: defaults)

        store.observe(.russian, applicationBundleIdentifier: "test.app")
        store.observe(.russian, applicationBundleIdentifier: "test.app")
        XCTAssertNil(store.preferredLanguage(for: "test.app"))
        store.observe(.russian, applicationBundleIdentifier: "test.app")
        XCTAssertEqual(store.preferredLanguage(for: "test.app"), .russian)
        store.flush()
        let restored = ApplicationLanguageProfileStore(defaults: defaults)
        XCTAssertEqual(restored.preferredLanguage(for: "test.app"), .russian)
    }
}
