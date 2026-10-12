import XCTest
@testable import ShoevSwitcher

final class RussianPunctuationEngineTests: XCTestCase {
    private let engine = RussianPunctuationEngine()

    func testSeparatesSubordinateClause() {
        XCTAssertEqual(engine.punctuate("я думаю что ты прав"), "я думаю, что ты прав")
        XCTAssertEqual(engine.punctuate("мы остались потому что шёл дождь"), "мы остались, потому что шёл дождь")
        XCTAssertEqual(engine.punctuate("я позвоню даже если будет поздно"), "я позвоню, даже если будет поздно")
        XCTAssertEqual(engine.punctuate("мы остановились для того чтобы отдохнуть"), "мы остановились, для того чтобы отдохнуть")
        XCTAssertEqual(engine.punctuate("позвони перед тем как приедешь"), "позвони, перед тем как приедешь")
    }

    func testSeparatesAdversativeAndPairedConjunctions() {
        XCTAssertEqual(engine.punctuate("не красный а синий"), "не красный, а синий")
        XCTAssertEqual(engine.punctuate("как дети так и взрослые"), "как дети, так и взрослые")
        XCTAssertEqual(engine.punctuate("я купил и яблоки и груши"), "я купил и яблоки, и груши")
    }

    func testSetsOffIntroductoryWordsAndPhrases() {
        XCTAssertEqual(engine.punctuate("конечно мы придём"), "конечно, мы придём")
        XCTAssertEqual(engine.punctuate("мы к сожалению опоздали"), "мы, к сожалению, опоздали")
        XCTAssertEqual(engine.punctuate("итак начнём"), "итак, начнём")
        XCTAssertEqual(engine.punctuate("это например хороший вариант"), "это, например, хороший вариант")
        XCTAssertEqual(engine.punctuate("например начнём отсюда"), "например, начнём отсюда")
        XCTAssertEqual(engine.punctuate("он вероятно уже приехал"), "он, вероятно, уже приехал")
        XCTAssertEqual(engine.punctuate("честно говоря я устал"), "честно говоря, я устал")
    }

    func testAddsCommaAfterGreeting() {
        XCTAssertEqual(engine.punctuate("привет Маша"), "привет, Маша")
        XCTAssertEqual(engine.punctuate("здравствуйте коллеги"), "здравствуйте, коллеги")
        XCTAssertEqual(engine.punctuate("добрый день коллеги"), "добрый день, коллеги")
    }

    func testSetsOffLikelyAddresses() {
        XCTAssertEqual(engine.punctuate("Маша принеси чай"), "Маша, принеси чай")
        XCTAssertEqual(engine.punctuate("Иван Иванович посмотрите сюда"), "Иван Иванович, посмотрите сюда")
        XCTAssertEqual(engine.punctuate("ребята давайте начнём"), "ребята, давайте начнём")
        XCTAssertEqual(engine.punctuate("спасибо Маша"), "спасибо, Маша")
        XCTAssertEqual(engine.punctuate("как дела Маша"), "как дела, Маша")
    }

    func testSeparatesExplanatoryConstructions() {
        XCTAssertEqual(engine.punctuate("нужен специалист то есть врач"), "нужен специалист, то есть врач")
        XCTAssertEqual(engine.punctuate("купили фрукты в том числе яблоки"), "купили фрукты, в том числе яблоки")
    }

    func testPreservesManualPunctuationAndAvoidsKnownFalsePositives() {
        XCTAssertEqual(engine.punctuate("я думаю, что ты прав"), "я думаю, что ты прав")
        XCTAssertEqual(engine.punctuate("и тогда он пришёл и всё рассказал"), "и тогда он пришёл и всё рассказал")
        XCTAssertEqual(engine.punctuate("он спросил что ли это правда"), "он спросил что ли это правда")
        XCTAssertEqual(engine.punctuate("кот похож на льва как две капли воды"), "кот похож на льва как две капли воды")
    }

    func testDoesNotTouchURLsOrEnglishText() {
        XCTAssertEqual(engine.punctuate("открой https://example.com когда сможешь"), "открой https://example.com когда сможешь")
        XCTAssertEqual(engine.punctuate("hello but no punctuation"), "hello but no punctuation")
    }

    func testChoosesTerminalMark() {
        XCTAssertEqual(engine.terminalMark(for: "почему небо синее"), "?")
        XCTAssertEqual(engine.terminalMark(for: "приедешь ли ты завтра"), "?")
        XCTAssertEqual(engine.terminalMark(for: "сегодня хорошая погода"), ".")
    }

    func testCapitalizesFirstTypedLetter() {
        XCTAssertEqual(engine.capitalized("п"), "П")
        XCTAssertEqual(engine.capitalized("hello"), "Hello")
        XCTAssertEqual(engine.capitalized("Я"), "Я")
    }

    func testDoesNotTreatSentenceMembersAsIntroductoryWords() {
        for text in ["это возможно", "путь короче", "мне кажется", "главное блюдо готово",
                     "это должно быть здесь", "он может быть дома", "всё само собой получилось",
                     "говори по существу", "мы сделали это таким образом"] {
            XCTAssertEqual(engine.punctuate(text), text, text)
        }
    }

    func testDoesNotGuessAddressesFromCapitalization() {
        for text in ["Завтра приходите", "Потом сделай", "Спасибо большое", "Извини меня",
                     "как работает Интернет"] {
            XCTAssertEqual(engine.punctuate(text), text, text)
        }
    }

    func testWaitsForConjunctionLookahead() {
        XCTAssertEqual(engine.punctuate("он спросил что "), "он спросил что ")
        XCTAssertEqual(engine.punctuate("он спросил что ли "), "он спросил что ли ")
        XCTAssertEqual(engine.punctuate("возьми хотя бы книгу"), "возьми хотя бы книгу")
        XCTAssertEqual(engine.punctuate("я думаю что ты "), "я думаю, что ты ")
    }

    func testIndirectQuestionDoesNotBecomeDirectQuestion() {
        XCTAssertEqual(engine.terminalMark(for: "я не знаю придёт ли он"), ".")
        XCTAssertEqual(engine.terminalMark(for: "он спросил что ли это правда"), ".")
        XCTAssertEqual(engine.terminalMark(for: "не приедешь ли ты"), "?")
    }
}
