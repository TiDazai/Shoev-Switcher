import AppKit
import ApplicationServices

struct CaretContext {
    let prefix: String
    let selectionLength: Int
    var nextCharacter: Character? = nil
    var element: AXUIElement? = nil
    var fullText: String? = nil

    func matches(_ other: CaretContext) -> Bool {
        sameField(as: other) && prefix == other.prefix && selectionLength == other.selectionLength
            && nextCharacter == other.nextCharacter
            && fullText == other.fullText
    }

    func sameField(as other: CaretContext) -> Bool {
        if let element, let otherElement = other.element {
            return CFEqual(element, otherElement)
        }
        return element == nil && other.element == nil
    }

    var startsInsideWord: Bool {
        func isToken(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.isLetter || character.isNumber || "@#/_\\-'’".contains(character)
        }
        return isToken(prefix.last) || isToken(nextCharacter)
    }
}

enum CapitalizationContext {
    static func shouldCapitalize(after prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        if last == "\n" || last == "\r" { return true }
        if "«„“".contains(last) { return true }
        if last == "\"" {
            // A straight quote after a word is usually a closing quote.
            let before = trimmed.dropLast()
            return before.last?.isLetter != true && before.last?.isNumber != true
        }
        var ending = trimmed
        while let character = ending.last, "»”’\")]}".contains(character) {
            ending.removeLast()
        }
        guard let mark = ending.last, ".!?…".contains(mark) else { return false }
        if mark == "." {
            let token = ending.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            // Avoid decimals, versions, initials and common abbreviations.
            if token.contains(where: { $0.isNumber }) { return false }
            let abbreviations: Set<String> = ["т.", "д.", "п.", "е.", "г.", "гг.", "ул.", "д-р.", "им.", "рис.", "стр.", "см.", "др.", "пр.", "руб.", "коп.", "тыс.", "млн.", "млрд.", "mr.", "mrs.", "dr.", "etc."]
            if abbreviations.contains(token.lowercased()) { return false }
            if token.count == 2, token.first?.isLetter == true { return false }
            if token.dropLast().contains(".") && !token.hasSuffix("...") { return false }
        }
        return true
    }
}


final class CaretContextReader {
    func read() -> CaretContext? {
        VerifiedCaretContextReader().read()
    }
}
