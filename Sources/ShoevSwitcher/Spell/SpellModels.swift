import Foundation

enum SpellLanguage: Int32, CaseIterable {
    case english = 0
    case russian = 1

    static func detect(in word: String) -> SpellLanguage? {
        var latin = 0
        var cyrillic = 0
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A: latin += 1
            case 0x0410...0x044F, 0x0401, 0x0451: cyrillic += 1
            default:
                if CharacterSet.letters.contains(scalar) { return nil }
            }
        }
        guard latin > 0 || cyrillic > 0, latin == 0 || cyrillic == 0 else { return nil }
        return cyrillic > latin ? .russian : .english
    }

    var alphabet: [Character] {
        switch self {
        case .english: return Array("abcdefghijklmnopqrstuvwxyz")
        case .russian: return Array("абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
        }
    }
}

struct SpellingCandidate: Equatable {
    let word: String
    let score: Int
}

struct Correction: Equatable {
    let original: String
    let replacement: String
}
