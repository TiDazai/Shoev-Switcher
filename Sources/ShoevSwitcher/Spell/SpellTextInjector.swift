import AppKit

protocol SpellTextInjecting {
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?, context: CaretContext) -> Bool
    func replaceAfterDelimiter(deleteCount: Int, with replacement: String, trailingEvent: CGEvent,
                               context: CaretContext, completion: @escaping () -> Void) -> Bool
}

extension SpellTextInjecting {
    func replaceAfterDelimiter(deleteCount: Int, with replacement: String, trailingEvent: CGEvent,
                               context: CaretContext, completion: @escaping () -> Void) -> Bool {
        let consumed = replace(deleteCount: deleteCount, with: replacement, trailingEvent: trailingEvent, context: context)
        if consumed { completion() }
        return consumed
    }
}

/// An adapter, not another event injector: clipboard, selection verification,
/// secure-input guards and deferred edits are shared with Switcher.
final class SpellTextInjector: SpellTextInjecting {
    private let injector: TextReplacing
    init(injector: TextReplacing = EventInjector()) { self.injector = injector }

    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?, context: CaretContext) -> Bool {
        guard let field = field(context), deleteCount >= 0, deleteCount <= context.prefix.count else { return false }
        var original = String(context.prefix.suffix(deleteCount))
        var inserted = replacement
        if original.isEmpty {
            guard let previous = context.prefix.last else { return false }
            original = String(previous)
            inserted = original + replacement
        }
        return injector.replace(original: original, with: inserted, trailingEvent: trailingEvent, context: field)
    }

    func replaceAfterDelimiter(deleteCount: Int, with replacement: String, trailingEvent: CGEvent,
                               context: CaretContext, completion: @escaping () -> Void) -> Bool {
        guard let field = field(context), deleteCount >= 0, deleteCount <= context.prefix.count else { return false }
        return injector.replaceAfterDelimiter(original: String(context.prefix.suffix(deleteCount)),
            with: replacement, trailingEvent: trailingEvent, context: field, completion: completion)
    }

    private func field(_ context: CaretContext) -> TextReplacementContext? {
        guard let element = context.element, let text = context.fullText,
              context.selectionLength == 0, context.prefix.utf16.count <= text.utf16.count,
              (text as NSString).substring(to: context.prefix.utf16.count) == context.prefix else { return nil }
        return TextReplacementContext(element: element, text: text,
            range: CFRange(location: context.prefix.utf16.count, length: 0),
            textOffset: context.textOffset, selectionTransport: context.selectionTransport)
    }
}

struct TextReplacement {
    let deleteCount: Int
    let text: String
    static func wasIgnored(before: String, expected: String, after: String?) -> Bool {
        EventInjector.wasIgnored(before: before, expected: expected, after: after)
    }
    init(original: String, replacement: String) {
        let shared = zip(original, replacement).prefix { $0 == $1 }.count
        deleteCount = original.count - shared
        text = String(replacement.dropFirst(shared))
    }
}
