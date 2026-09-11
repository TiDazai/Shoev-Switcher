import ApplicationServices
import XCTest
@testable import ShoevSwitcher

final class TextInputAccessibilityTraitsTests: XCTestCase {
    func testEditableTextFieldIsDetected() {
        XCTAssertTrue(TextInputAccessibilityTraits.isEditable(
            role: kAXTextFieldRole as String,
            subrole: nil,
            editableAttribute: false,
            valueIsSettable: true
        ))
    }

    func testSecureTextFieldIsNeverDetected() {
        XCTAssertFalse(TextInputAccessibilityTraits.isEditable(
            role: kAXTextFieldRole as String,
            subrole: kAXSecureTextFieldSubrole as String,
            editableAttribute: true,
            valueIsSettable: true
        ))
    }

    func testReadOnlyTextIsNotDetected() {
        XCTAssertFalse(TextInputAccessibilityTraits.isEditable(
            role: kAXStaticTextRole as String,
            subrole: nil,
            editableAttribute: false,
            valueIsSettable: false
        ))
    }
}
