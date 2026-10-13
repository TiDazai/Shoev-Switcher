import Foundation
import CoreGraphics

enum InputLanguage: String, Codable, CaseIterable {
    case english = "en"
    case russian = "ru"

    var title: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

struct KeyStroke: Equatable {
    let keyCode: CGKeyCode
    let visibleText: String
    let shouldUppercase: Bool

    init(keyCode: CGKeyCode, visibleText: String, shouldUppercase: Bool = false) {
        self.keyCode = keyCode
        self.visibleText = visibleText
        self.shouldUppercase = shouldUppercase
    }
}

struct TypedToken: Equatable {
    var strokes: [KeyStroke] = []

    var visibleText: String {
        strokes.map(\.visibleText).joined()
    }

    var isEmpty: Bool { strokes.isEmpty }

    mutating func append(_ stroke: KeyStroke) {
        strokes.append(stroke)
    }

    mutating func removeLast() {
        if !strokes.isEmpty { strokes.removeLast() }
    }

    mutating func clear() {
        strokes.removeAll(keepingCapacity: true)
    }
}

struct ConversionCandidate: Equatable {
    let original: String
    let replacement: String
    let sourceLanguage: InputLanguage
    let targetLanguage: InputLanguage
}

enum DetectionDecision: Equatable {
    case keep
    case convert(ConversionCandidate)
}

struct DetectionContext: Equatable {
    var recentLanguages: [InputLanguage] = []
    var recentTokens: [ContextToken] = []
    var applicationLanguage: InputLanguage?

    var dominantLanguage: InputLanguage? {
        guard !recentLanguages.isEmpty else { return nil }
        let english = recentLanguages.filter { $0 == .english }.count
        let russian = recentLanguages.count - english
        guard english != russian else { return recentLanguages.last }
        return english > russian ? .english : .russian
    }
}

enum ManualShortcut: String, CaseIterable {
    case rightShift
    case leftShift

    var keyCode: CGKeyCode {
        switch self {
        case .rightShift: return 60
        case .leftShift: return 56
        }
    }

    var title: String {
        switch self {
        case .rightShift: return "Двойной правый Shift"
        case .leftShift: return "Двойной левый Shift"
        }
    }
}

struct ContextToken: Equatable {
    let text: String
    let language: InputLanguage
}

struct DetectionEvaluation: Equatable {
    let decision: DetectionDecision
    let likelyLanguage: InputLanguage
}

struct CompletedToken {
    let displayedText: String
    let alternativeText: String
    let displayedLanguage: InputLanguage
    let alternativeLanguage: InputLanguage
    let terminator: String
    let processIdentifier: pid_t
    let completedAt: Date
    let correctionKind: JournalEventKind?

    init(
        displayedText: String,
        alternativeText: String,
        displayedLanguage: InputLanguage,
        alternativeLanguage: InputLanguage,
        terminator: String,
        processIdentifier: pid_t,
        completedAt: Date,
        correctionKind: JournalEventKind? = nil
    ) {
        self.displayedText = displayedText
        self.alternativeText = alternativeText
        self.displayedLanguage = displayedLanguage
        self.alternativeLanguage = alternativeLanguage
        self.terminator = terminator
        self.processIdentifier = processIdentifier
        self.completedAt = completedAt
        self.correctionKind = correctionKind
    }
}

enum RuleKind: String, Codable {
    case keep
    case convert
    case accept
}

struct UserRule: Codable, Identifiable, Equatable {
    let id: Int64
    let kind: RuleKind
    let pattern: String
    let replacement: String?
    let language: InputLanguage?
    let applicationBundleIdentifier: String?
    let createdAt: Date
    var module: CorrectionModule? = nil
    var origin: PersonalOrigin? = nil
    var enabled: Bool? = nil
    var targetLanguage: InputLanguage? = nil
    var confirmations: Int? = nil
    var isEnabled: Bool { enabled != false }
}

struct LearningEntry: Identifiable, Equatable {
    let id: Int64
    let original: String
    let replacement: String
    let sourceLanguage: InputLanguage
    let targetLanguage: InputLanguage
    let correctionCount: Int
    let updatedAt: Date
    let learnedRuleID: Int64?

    var isLearned: Bool { learnedRuleID != nil }
}

enum JournalEventKind: String, Codable {
    case spelling
    case correction
    case manualCorrection
    case typed
    case undone
}

struct JournalEntry: Codable, Identifiable, Equatable {
    let id: Int64
    let createdAt: Date
    let applicationBundleIdentifier: String?
    let applicationName: String?
    let original: String
    let replacement: String?
    let sourceLanguage: InputLanguage?
    let targetLanguage: InputLanguage?
    let kind: JournalEventKind
    var eventID: String? = nil
    var outcome: FeedbackOutcome? = nil
}

enum CorrectionModule: String, Codable, CaseIterable {
    case switcher, spell
    var title: String { self == .switcher ? "Switcher" : "Spell" }
}

enum PersonalOrigin: String, Codable, CaseIterable {
    case manual, diary, learning
    var title: String {
        switch self { case .manual: return "Добавлено вручную"; case .diary: return "Из дневника"; case .learning: return "Самообучение" }
    }
}

enum FeedbackOutcome: String, Codable, CaseIterable {
    case pending, accepted, rejected, edited, unverified
    var title: String {
        switch self {
        case .pending: return "Ожидает проверки"
        case .accepted: return "Сохранено пользователем"
        case .rejected: return "Отменено пользователем"
        case .edited: return "Удалено или изменено"
        case .unverified: return "Не подтверждено"
        }
    }
}

struct PersonalWord: Identifiable, Codable, Equatable {
    let id: String
    let word: String
    let language: InputLanguage
    let origin: PersonalOrigin
    let applicationBundleIdentifier: String?
    let ruleID: Int64?
    let createdAt: Date
    var module: CorrectionModule? = nil
    var scopeTitle: String { (module.map { $0.title + " · " } ?? "") + (applicationBundleIdentifier ?? "Все приложения") }
}

struct AdaptiveObservation: Identifiable, Equatable {
    let id: String
    let pattern: String
    let replacement: String?
    let sourceLanguage: InputLanguage
    let targetLanguage: InputLanguage
    let module: CorrectionModule
    let kind: RuleKind
    let applicationBundleIdentifier: String?
    let confirmations: Int
    let lastConfirmedAt: Date
    let learnedRuleID: Int64?
}

struct LearningProof {
    let id: String
    let pattern: String
    let replacement: String?
    let sourceLanguage: InputLanguage
    let targetLanguage: InputLanguage
    let module: CorrectionModule
    let kind: RuleKind
    let applicationBundleIdentifier: String?
    let confirmedAt: Date
}

enum PersonalWordValidation {
    static func normalized(_ word: String, language: InputLanguage) -> String? {
        let value = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "en_US_POSIX")).precomposedStringWithCanonicalMapping
        guard (1...64).contains(value.count), value.first?.isLetter == true, value.last?.isLetter == true else { return nil }
        let alphabet = language == .english ? CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
            : CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
        guard value.unicodeScalars.allSatisfy({ alphabet.contains($0) || "-'’".unicodeScalars.contains($0)
            || (language == .english && (0x00C0...0x024F).contains($0.value) && CharacterSet.letters.contains($0)) }) else { return nil }
        return value
    }
}
