import Foundation

/// Restores only punctuation that can be inferred with high confidence from the
/// words already typed. It deliberately avoids semantic cases (for example,
/// comparisons with "как" and most detached modifiers) where a local rule would
/// produce distracting false positives.
final class RussianPunctuationEngine {
    private struct Token {
        let value: String
        let range: NSRange
    }

    private let adversativeConjunctions: Set<String> = ["а", "но", "зато", "однако"]
    private let subordinateConjunctions: Set<String> = [
        "что", "чтобы", "если", "когда", "пока", "хотя", "поскольку",
        "где", "куда", "откуда", "который", "которая", "которое", "которые",
        "которого", "которой", "которых", "которому", "которым", "которыми"
    ]
    private let conjunctionModifiers: Set<String> = ["даже", "только", "лишь", "особенно"]
    private let compoundConjunctions: [[String]] = [
        ["благодаря", "тому", "что"], ["в", "то", "время", "как"],
        ["ввиду", "того", "что"], ["вместо", "того", "чтобы"],
        ["вследствие", "того", "что"], ["для", "того", "чтобы"],
        ["до", "того", "как"], ["из-за", "того", "что"],
        ["как", "будто"], ["несмотря", "на", "то", "что"],
        ["невзирая", "на", "то", "что"], ["перед", "тем", "как"],
        ["по", "мере", "того", "как"], ["после", "того", "как"],
        ["потому", "что"], ["с", "тем", "чтобы"],
        ["с", "тех", "пор", "как"], ["так", "как"], ["так", "что"]
    ].sorted { $0.count > $1.count }
    private let interrogativeOpeners: Set<String> = [
        "кто", "что", "где", "куда", "откуда", "когда", "как", "зачем", "почему",
        "сколько", "чей", "чья", "чьё", "чьи", "какой", "какая", "какое", "какие"
    ]
    private let introductoryPhrases: [[String]] = [
        ["без", "сомнения"], ["без", "шуток"],
        ["в", "общем"], ["в", "сущности"],
        ["в", "частности"], ["во", "всяком", "случае"],
        ["вне", "всякого", "сомнения"],
        ["другими", "словами"], ["иначе", "говоря"], ["как", "всегда"],
        ["как", "говорится"], ["к", "несчастью"], ["к", "огорчению"],
        ["к", "радости"], ["к", "сожалению"], ["к", "счастью"],
        ["к", "стыду"], ["к", "удивлению"], ["между", "прочим"],
        ["надо", "признаться"],
        ["по", "всей", "вероятности"], ["по", "правде", "говоря"],
        ["прямо", "скажем"], ["собственно", "говоря"],
        ["стало", "быть"], ["строго", "говоря"], ["судя", "по", "всему"],
        ["так", "сказать"], ["честно", "говоря"]
    ]
    private let introductoryWords: Set<String> = [
        "безусловно", "бесспорно", "вероятно", "видимо", "во-первых",
        "во-вторых", "во-третьих", "впрочем", "итак", "конечно", "кстати",
        "наверное", "например", "несомненно", "пожалуй", "по-видимому",
        "по-моему", "по-твоему", "разумеется", "следовательно"
    ]
    // Capitalization alone cannot distinguish a name from "Завтра" or "Потом".
    private let commonNames: Set<String> = [
        "александр", "алексей", "анна", "антон", "артём", "артем", "борис",
        "вадим", "валентина", "василий", "виктор", "владимир", "галина",
        "дарья", "дима", "дмитрий", "евгений", "екатерина", "елена", "иван",
        "игорь", "ирина", "катя", "ксения", "мария", "марина", "маша",
        "михаил", "наталья", "никита", "николай", "олег", "ольга", "павел",
        "пётр", "петр", "роман", "саша", "светлана", "сергей", "татьяна",
        "тима", "тимофей", "юлия", "юрий"
    ]
    private static let tokenExpression = try! NSRegularExpression(pattern: "[А-Яа-яЁё]+(?:-[А-Яа-яЁё]+)*")
    private let addressWords: Set<String> = [
        "бабушка", "брат", "братья", "господа", "граждане", "дамы", "дедушка",
        "доктор", "друзья", "друг", "коллега", "коллеги", "мама", "мам",
        "мужчина", "папа", "пап", "подруга", "ребята", "сестра", "товарищи",
        "уважаемые", "уважаемый", "уважаемая", "учитель"
    ]
    private let imperativeWords: Set<String> = [
        "будем", "будьте", "возьми", "возьмите", "давай", "давайте", "дай",
        "дайте", "запомни", "запомните", "напиши", "напишите", "начинай",
        "начинайте", "позвони", "позвоните", "помоги", "помогите", "послушай",
        "послушайте", "посмотри", "посмотрите", "приходи", "приходите", "принеси",
        "принесите", "скажи", "скажите", "сделай", "сделайте"
    ]

    func punctuate(_ text: String) -> String {
        guard shouldProcess(text) else { return text }
        let tokens = tokenize(text)
        guard tokens.count > 1 else { return text }

        var commaOffsets = Set<Int>()
        addClauseCommas(tokens, in: text, to: &commaOffsets)
        addIntroductoryCommas(tokens, in: text, to: &commaOffsets)
        addRepeatedConjunctionCommas(tokens, in: text, to: &commaOffsets)
        addGreetingComma(tokens, in: text, to: &commaOffsets)
        addAddressCommas(tokens, in: text, to: &commaOffsets)
        addExplanatoryCommas(tokens, in: text, to: &commaOffsets)
        return insertingCommas(at: commaOffsets, into: text)
    }

    func terminalMark(for text: String) -> Character {
        let tokens = tokenize(text)
        guard let first = tokens.first?.value else { return "." }
        let directLi = tokens.count > 1 && tokens[1].value == "ли"
            || tokens.count > 2 && first == "не" && tokens[2].value == "ли"
        if interrogativeOpeners.contains(first) || directLi {
            return "?"
        }
        return "."
    }

    func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: Locale(identifier: "ru_RU")) + text.dropFirst()
    }

    private func shouldProcess(_ text: String) -> Bool {
        guard text.count <= 500,
              text.unicodeScalars.contains(where: { (0x0400...0x052F).contains($0.value) }) else { return false }
        let unsafe = CharacterSet(charactersIn: "@#/:\\")
        return text.rangeOfCharacter(from: unsafe) == nil
    }

    private func tokenize(_ text: String) -> [Token] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return Self.tokenExpression.matches(in: text, range: fullRange).map {
            Token(value: (text as NSString).substring(with: $0.range).lowercased(), range: $0.range)
        }
    }

    private func addClauseCommas(_ tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        for index in tokens.indices.dropFirst() {
            let token = tokens[index].value
            if adversativeConjunctions.contains(token) {
                addComma(before: index, tokens: tokens, in: text, to: &offsets)
                continue
            }

            var conjunctionStart = compoundConjunctionStart(endingAt: index, tokens: tokens) ?? index
            if conjunctionStart == index, subordinateConjunctions.contains(token) == false {
                continue
            }
            // Wait for the next word: "что ли" and "хотя бы" must not acquire
            // an irreversible comma when only the conjunction has been typed.
            guard index + 1 < tokens.count else { continue }

            if token == "что", index + 1 < tokens.count,
               ["бы", "ли", "за"].contains(tokens[index + 1].value) { continue }
            if token == "что", index > 0,
               ["за", "про", "ни"].contains(tokens[index - 1].value) { continue }
            if token == "хотя", index + 1 < tokens.count, tokens[index + 1].value == "бы" { continue }
            if conjunctionStart > 0, conjunctionModifiers.contains(tokens[conjunctionStart - 1].value) {
                conjunctionStart -= 1
            }
            guard conjunctionStart > 0 else { continue }
            addComma(before: conjunctionStart, tokens: tokens, in: text, to: &offsets)
        }
    }

    private func compoundConjunctionStart(endingAt index: Int, tokens: [Token]) -> Int? {
        for phrase in compoundConjunctions {
            guard phrase.count <= index + 1 else { continue }
            let start = index + 1 - phrase.count
            if Array(tokens[start...index].map(\.value)) == phrase { return start }
        }
        return nil
    }

    private func addIntroductoryCommas(_ tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        for index in tokens.indices where introductoryWords.contains(tokens[index].value) {
            if index > 0 { addComma(before: index, tokens: tokens, in: text, to: &offsets) }
            if index + 1 < tokens.count { addComma(after: index, tokens: tokens, in: text, to: &offsets) }
        }

        for phrase in introductoryPhrases where phrase.count <= tokens.count {
            for start in 0...(tokens.count - phrase.count) {
                guard Array(tokens[start..<(start + phrase.count)].map(\.value)) == phrase else { continue }
                if start > 0 { addComma(before: start, tokens: tokens, in: text, to: &offsets) }
                if start + phrase.count < tokens.count {
                    addComma(after: start + phrase.count - 1, tokens: tokens, in: text, to: &offsets)
                }
            }
        }
    }

    private func addRepeatedConjunctionCommas(_ tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        for conjunction in ["и", "или", "либо"] {
            let occurrences = tokens.indices.filter { tokens[$0].value == conjunction }
            guard let first = occurrences.first, first > 0 else { continue }
            for index in occurrences.dropFirst() {
                addComma(before: index, tokens: tokens, in: text, to: &offsets)
            }
        }
        if let first = tokens.firstIndex(where: { $0.value == "как" }),
           let second = tokens[(first + 1)...].firstIndex(where: { $0.value == "так" }) {
            addComma(before: second, tokens: tokens, in: text, to: &offsets)
        }
    }

    private func addGreetingComma(_ tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        let greetings: Set<String> = ["добрый", "привет", "здравствуй", "здравствуйте"]
        guard greetings.contains(tokens[0].value), tokens.count > 1 else { return }
        if tokens[0].value == "добрый" {
            guard tokens.count > 2, ["день", "вечер"].contains(tokens[1].value) else { return }
            addComma(after: 1, tokens: tokens, in: text, to: &offsets)
        } else {
            addComma(after: 0, tokens: tokens, in: text, to: &offsets)
        }
    }

    private func addAddressCommas(_ tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        guard tokens.count > 1 else { return }
        let attentionWords: Set<String> = ["спасибо", "извини", "извините", "простите", "пожалуйста"]

        if addressWords.contains(tokens[0].value), isLikelyImperative(tokens[1].value) {
            addComma(after: 0, tokens: tokens, in: text, to: &offsets)
        }
        if attentionWords.contains(tokens[0].value),
           tokens[0].value == "пожалуйста" || addressWords.contains(tokens[1].value) || commonNames.contains(tokens[1].value) {
            addComma(after: 0, tokens: tokens, in: text, to: &offsets)
        }
        if tokens.count > 2,
           commonNames.contains(tokens[0].value), isCapitalized(tokens[0], in: text),
           isCapitalized(tokens[1], in: text),
           tokens[1].value.hasSuffix("ич") || tokens[1].value.hasSuffix("на"),
           isLikelyImperative(tokens[2].value) {
            addComma(after: 1, tokens: tokens, in: text, to: &offsets)
        } else if commonNames.contains(tokens[0].value), isCapitalized(tokens[0], in: text), isLikelyImperative(tokens[1].value) {
            addComma(after: 0, tokens: tokens, in: text, to: &offsets)
        }
        if tokens.count > 2,
           interrogativeOpeners.contains(tokens[0].value),
           let last = tokens.last,
           commonNames.contains(last.value), isCapitalized(last, in: text) {
            addComma(before: tokens.count - 1, tokens: tokens, in: text, to: &offsets)
        }
    }

    private func addExplanatoryCommas(_ tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        for phrase in [["то", "есть"], ["а", "именно"], ["в", "том", "числе"]] {
            guard phrase.count <= tokens.count else { continue }
            for start in 0...(tokens.count - phrase.count) where start > 0 {
                if Array(tokens[start..<(start + phrase.count)].map(\.value)) == phrase {
                    addComma(before: start, tokens: tokens, in: text, to: &offsets)
                }
            }
        }
    }

    private func isCapitalized(_ token: Token, in text: String) -> Bool {
        let original = (text as NSString).substring(with: token.range)
        return original.first?.isUppercase == true
    }

    private func isLikelyImperative(_ word: String) -> Bool {
        imperativeWords.contains(word)
            || word.hasSuffix("йте")
            || word.hasSuffix("итесь")
            || word.hasSuffix("айте")
            || word.hasSuffix("яйте")
    }

    private func addComma(before index: Int, tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        guard index > 0 else { return }
        let position = tokens[index - 1].range.location + tokens[index - 1].range.length
        if needsComma(at: position, in: text) { offsets.insert(position) }
    }

    private func addComma(after index: Int, tokens: [Token], in text: String, to offsets: inout Set<Int>) {
        let position = tokens[index].range.location + tokens[index].range.length
        if needsComma(at: position, in: text) { offsets.insert(position) }
    }

    private func needsComma(at utf16Offset: Int, in text: String) -> Bool {
        let string = text as NSString
        var cursor = utf16Offset
        while cursor < string.length,
              let scalar = UnicodeScalar(string.character(at: cursor)),
              CharacterSet.whitespaces.contains(scalar) { cursor += 1 }
        if cursor < string.length, ",;:—–-.!?…".utf16.contains(string.character(at: cursor)) { return false }
        if utf16Offset > 0, ",;:—–-".utf16.contains(string.character(at: utf16Offset - 1)) { return false }
        return true
    }

    private func insertingCommas(at offsets: Set<Int>, into text: String) -> String {
        let result = NSMutableString(string: text)
        for offset in offsets.sorted(by: >) { result.insert(",", at: offset) }
        return result as String
    }
}
