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

    var dominantLanguage: InputLanguage? {
        guard !recentLanguages.isEmpty else { return nil }
        let english = recentLanguages.filter { $0 == .english }.count
        let russian = recentLanguages.count - english
        guard english != russian else { return recentLanguages.last }
        return english > russian ? .english : .russian
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
}

enum JournalEventKind: String, Codable {
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
}
