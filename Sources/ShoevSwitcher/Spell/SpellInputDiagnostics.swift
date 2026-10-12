import Foundation
import OSLog

enum SpellInputDiagnostic: String {
    case missingFocus = "Не удалось получить активное поле."
    case missingRange = "Поле не предоставляет положение курсора."
    case missingValue = "Поле не предоставляет текст для проверки."
    case invalidRange = "Редактор вернул некорректный диапазон курсора."
    case secureField = "Защищённый ввод: исправления запрещены."
    case contextChanged = "Поле или текст изменились перед исправлением."
    case selectionReadOnly = "Поле не разрешает управление выделением."
    case replacementUnsupported = "Поле не поддерживает безопасную замену текста."
    case selectionPending = "Редактор не подтвердил изменение выделения."
    case replacementFailed = "Редактор отклонил замену текста."
    case replacementIgnored = "Редактор подтвердил запрос, но текст не изменился."
    case replacementUnverified = "Результат замены пока не подтверждён редактором."
    case correctedSelection = "Исправление выполнено через замену выделения."
    case correctedMarker = "Исправление выполнено через текстовый диапазон редактора."
    case correctedValue = "Исправление выполнено через значение простого текстового поля."
    case correctedPaste = "Исправление подтверждено после резервной вставки."
    case pastePending = "Резервная вставка отправлена, ожидается подтверждение."
}

/// Only fixed reason codes are kept: no words, clipboard data or field contents.
final class SpellInputDiagnostics {
    static let shared = SpellInputDiagnostics()
    private let logger = Logger(subsystem: "com.shoev.spell", category: "compatibility")
    private(set) var latest: SpellInputDiagnostic?
    private var lastLogged: SpellInputDiagnostic?
    private var lastLogTime = Date.distantPast

    func record(_ reason: SpellInputDiagnostic) {
        latest = reason
        let now = Date()
        guard reason != lastLogged || now.timeIntervalSince(lastLogTime) >= 3 else { return }
        lastLogged = reason
        lastLogTime = now
        logger.info("Input compatibility: \(String(describing: reason), privacy: .public)")
    }
}
