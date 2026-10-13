import AppKit
import XCTest
@testable import ShoevSwitcher

final class AdaptiveLearningTests: XCTestCase {
    func testAutomaticCorrectionsNeverTeachThemselves() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .correction)
        fixture.continueAfterCorrection()
        XCTAssertEqual(fixture.outcomes.last, .accepted)
        XCTAssertTrue(fixture.proofs.isEmpty)
    }
    func testManualCorrectionRequiresTimeAndContinuedInput() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .manualCorrection)
        fixture.time = 10
        fixture.controller.evaluate(context: fixture.context, boundary: false)
        XCTAssertEqual(fixture.controller.pendingCount, 1)
        XCTAssertTrue(fixture.proofs.isEmpty)
        fixture.continueAfterCorrection()
        XCTAssertEqual(fixture.proofs.count, 1)
        XCTAssertEqual(fixture.proofs.first?.kind, .convert)
    }
    func testDeletingACorrectionDoesNotCreateARule() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .manualCorrection)
        fixture.text = ""
        fixture.controller.evaluate(context: fixture.context, boundary: false)
        XCTAssertEqual(fixture.outcomes.last, .edited)
        XCTAssertTrue(fixture.proofs.isEmpty)
        XCTAssertEqual(fixture.controller.pendingCount, 0)
    }
    func testVerifiedUndoOnlyLearnsTheKeptWordAfterConfirmation() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .correction)
        fixture.text = "ghbdtn "
        fixture.controller.record(JournalEntry(id: 0, createdAt: Date(), applicationBundleIdentifier: "com.example.Editor",
            applicationName: nil, original: "привет", replacement: "ghbdtn", sourceLanguage: .russian,
            targetLanguage: .english, kind: .undone), module: .switcher, journalEnabled: true)
        XCTAssertEqual(fixture.outcomes.last, .rejected)
        XCTAssertTrue(fixture.proofs.isEmpty)
        fixture.continueAfterCorrection()
        XCTAssertEqual(fixture.proofs.first?.kind, .keep)
        XCTAssertEqual(fixture.proofs.first?.pattern, "ghbdtn")
    }
    func testChangingApplicationOrFocusNeverTeaches() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .manualCorrection)
        fixture.app = "com.other.Editor"
        fixture.controller.evaluate(context: fixture.context, boundary: true, submitted: true)
        XCTAssertEqual(fixture.outcomes.last, .unverified)
        XCTAssertTrue(fixture.proofs.isEmpty)
    }
    func testUnknownFieldNeverTeaches() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .manualCorrection)
        fixture.controller.evaluate(context: nil, boundary: true)
        XCTAssertEqual(fixture.outcomes.last, .unverified)
        XCTAssertTrue(fixture.proofs.isEmpty)
    }
    func testIdenticalTextInADifferentParagraphNeverTeaches() {
        let fixture = FeedbackFixture()
        fixture.offset = 200
        fixture.record(kind: .manualCorrection)
        fixture.offset = 500
        fixture.controller.evaluate(context: fixture.context, boundary: true, submitted: true)
        XCTAssertEqual(fixture.outcomes.last, .unverified)
        XCTAssertTrue(fixture.proofs.isEmpty)
    }
    func testSubmitConfirmsAManualResultWithoutConsumingAKey() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .manualCorrection)
        fixture.controller.evaluate(context: fixture.context, boundary: true, submitted: true)
        XCTAssertEqual(fixture.proofs.count, 1)
        XCTAssertEqual(fixture.outcomes.last, .accepted)
    }
    func testLearningCanBeDisabledIndependentlyOfJournal() {
        let fixture = FeedbackFixture()
        fixture.defaults.set(false, forKey: PreferenceKey.automaticLearning)
        fixture.record(kind: .manualCorrection)
        fixture.continueAfterCorrection()
        XCTAssertEqual(fixture.outcomes.last, .accepted)
        XCTAssertTrue(fixture.proofs.isEmpty)
    }
    func testPendingMemoryIsBoundedAndCancellationCannotTeach() {
        let fixture = FeedbackFixture()
        for _ in 0..<12 { fixture.record(kind: .manualCorrection) }
        XCTAssertEqual(fixture.controller.pendingCount, 8)
        fixture.controller.cancelAll()
        XCTAssertEqual(fixture.controller.pendingCount, 0)
        XCTAssertTrue(fixture.proofs.isEmpty)
    }

    func testSpacesAloneAreNotEvidenceOfContinuedWriting() {
        let fixture = FeedbackFixture()
        fixture.record(kind: .manualCorrection)
        fixture.time = 10; fixture.text += "     "
        fixture.controller.evaluate(context: fixture.context, boundary: true)
        XCTAssertTrue(fixture.proofs.isEmpty)
        XCTAssertEqual(fixture.controller.pendingCount, 1)
    }

    func testSecureInputNeverReadsAnEditorOrLearns() {
        let suite = "SecureLearning-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: defaults)
        var reads = 0; var proofs = 0
        let controller = AdaptiveLearningController(store: nil, defaults: defaults,
            readContext: { reads += 1; return nil }, schedule: { _, _ in },
            proofObserver: { _ in proofs += 1 }, secureInput: { true })
        controller.record(JournalEntry(id: 0, createdAt: Date(), applicationBundleIdentifier: "com.example.Editor",
            applicationName: nil, original: "ghbdtn", replacement: "привет", sourceLanguage: .english,
            targetLanguage: .russian, kind: .manualCorrection), module: .switcher, journalEnabled: true)
        XCTAssertEqual(reads, 0); XCTAssertEqual(proofs, 0); XCTAssertEqual(controller.pendingCount, 0)
    }
    func testUserRepairBecomesEvidenceOnlyAfterItIsKept() {
        let fixture = FeedbackFixture()
        fixture.text = "hello "
        fixture.controller.record(JournalEntry(id: 0, createdAt: Date(), applicationBundleIdentifier: fixture.app,
            applicationName: nil, original: "helo", replacement: "hello", sourceLanguage: .english,
            targetLanguage: .english, kind: .spelling), module: .spell, journalEnabled: true)
        fixture.text = ""
        fixture.controller.evaluate(context: fixture.context, boundary: false)
        fixture.text = "help "
        fixture.controller.evaluate(context: fixture.context, boundary: true)
        XCTAssertTrue(fixture.proofs.isEmpty)
        fixture.continueAfterCorrection()
        XCTAssertEqual(fixture.proofs.first?.pattern, "helo")
        XCTAssertEqual(fixture.proofs.first?.replacement, "help")
        XCTAssertEqual(fixture.proofs.first?.module, .spell)
    }
}

private final class FeedbackFixture {
    let element = AXUIElementCreateApplication(999_993)
    let defaults: UserDefaults
    private let suite = "FeedbackFixture-\(UUID())"
    var text = "привет "
    var time: TimeInterval = 0
    var app: String? = "com.example.Editor"
    var offset = 0
    var outcomes: [FeedbackOutcome] = []
    var proofs: [LearningProof] = []
    var context: TextReplacementContext { TextReplacementContext(element: element, text: text, range: CFRange(location: text.utf16.count, length: 0), textOffset: offset) }
    lazy var controller = AdaptiveLearningController(store: nil, defaults: defaults,
        readContext: { [unowned self] in self.context }, application: { [unowned self] in self.app }, now: { [unowned self] in Date(timeIntervalSince1970: self.time) },
        schedule: { _, _ in }, outcomeObserver: { [unowned self] _, outcome in self.outcomes.append(outcome) }, proofObserver: { [unowned self] in self.proofs.append($0) }, secureInput: { false })
    init() { defaults = UserDefaults(suiteName: suite)!; Preferences.registerDefaults(in: defaults) }
    deinit { defaults.removePersistentDomain(forName: suite) }
    func record(kind: JournalEventKind) {
        controller.record(JournalEntry(id: 0, createdAt: Date(), applicationBundleIdentifier: app,
            applicationName: nil, original: "ghbdtn", replacement: "привет", sourceLanguage: .english,
            targetLanguage: .russian, kind: kind), module: .switcher, journalEnabled: true)
    }
    func continueAfterCorrection() {
        time += 3; text += "первый "
        controller.evaluate(context: context, boundary: true)
        time += 3; text += "второй "
        controller.evaluate(context: context, boundary: true)
    }
}
