import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

protocol TextReplacing {
    func replace(original: String, with replacement: String, trailingEvent: CGEvent?, context: TextReplacementContext) -> Bool
    func replaceAfterDelimiter(original: String, with replacement: String, trailingEvent: CGEvent,
                               context: TextReplacementContext, completion: @escaping () -> Void) -> Bool
}
extension TextReplacing {
    func replaceAfterDelimiter(original: String, with replacement: String, trailingEvent: CGEvent,
                               context: TextReplacementContext, completion: @escaping () -> Void) -> Bool {
        let consumed = replace(original: original, with: replacement, trailingEvent: trailingEvent, context: context)
        if consumed { completion() }
        return consumed
    }
}

final class EventInjector: TextReplacing {
    static let syntheticEventMarker: Int64 = 0x53484F4556
    private let access: AccessibilityAccess
    private let readContext: () -> TextReplacementContext?
    private let secureInput: () -> Bool
    private let pasteOverride: ((String, TextReplacementContext, String) -> Bool)?
    private let logger = Logger(subsystem: "com.shoev.switcher", category: "replacement")
    private var generation = 0
    func cancelPending() { generation &+= 1 }

    init(access: AccessibilityAccess = AccessibilityAccess(),
         readContext: @escaping () -> TextReplacementContext? = { TextReplacementContextReader().read() },
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         pasteOverride: ((String, TextReplacementContext, String) -> Bool)? = nil) {
        self.access = access
        self.readContext = readContext
        self.secureInput = secureInput
        self.pasteOverride = pasteOverride
    }

    @discardableResult
    func replace(original: String, with replacement: String, trailingEvent: CGEvent? = nil, context: TextReplacementContext) -> Bool {
        perform(original: original, with: replacement, trailingEvent: trailingEvent, context: context)
    }

    func replaceAfterDelimiter(original: String, with replacement: String, trailingEvent: CGEvent,
                               context: TextReplacementContext, completion: @escaping () -> Void) -> Bool {
        guard let delimiter = Self.inlineDelimiter(trailingEvent), context.range.length == 0, !secureInput() else { return false }
        let postText = (context.text as NSString).replacingCharacters(
            in: NSRange(location: context.range.location, length: 0), with: delimiter)
        var attempts = 0
        let scheduledGeneration = generation
        func attempt() {
            attempts += 1
            guard self.generation == scheduledGeneration, !self.secureInput(),
                  let now = self.readContext(), CFEqual(now.element, context.element) else { return }
            if now.text == postText, now.range.location == context.range.location + delimiter.utf16.count,
               now.range.length == 0 {
                _ = self.perform(original: original + delimiter, with: replacement + delimiter,
                                 trailingEvent: nil, context: now, completion: completion)
            } else if now.matches(context), attempts < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: attempt)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: attempt)
        return false
    }

    private func perform(original: String, with replacement: String, trailingEvent: CGEvent? = nil,
                         context: TextReplacementContext, completion: @escaping () -> Void = {}) -> Bool {
        guard !secureInput(),
              context.range.length == 0,
              var range = TextReplacementContext.replacementRange(in: context.text, caret: context.range.location, original: original),
              let selectedRange = AXValueCreate(.cfRange, &range) else { return false }
        guard access.writable(context.element, kAXSelectedTextRangeAttribute) else { return false }
        let delimiter = trailingEvent.flatMap(Self.inlineDelimiter)
        guard trailingEvent == nil || delimiter != nil,
              readContext()?.matches(context) == true else { return false }
        guard access.set(context.element, kAXSelectedTextRangeAttribute, selectedRange) == .success else { return false }
        let insertedText = replacement + (delimiter ?? "")
        guard let selected = confirmSelection(context, range: range) else { return !restore(context) }
        let expectedText = (context.text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: insertedText)
        if access.writable(context.element, kAXSelectedTextAttribute) {
            guard readContext()?.matches(selected) == true else { return true }
            _ = access.set(context.element, kAXSelectedTextAttribute, insertedText as CFString)
            guard let after = readContext(), CFEqual(after.element, context.element) else { return true }
            if after.text == expectedText {
                var end = CFRange(location: range.location + insertedText.utf16.count, length: 0)
                if let value = AXValueCreate(.cfRange, &end) {
                    _ = access.set(context.element, kAXSelectedTextRangeAttribute, value)
                }
                logger.info("Replacement verified through selected text")
                completion()
                return true
            }
            // Only a verified no-op permits pasting over the same selection.
            if !after.matches(selected) {
                guard after.matches(context),
                      access.set(context.element, kAXSelectedTextRangeAttribute, selectedRange) == .success,
                      confirmSelection(context, range: range)?.matches(selected) == true else {
                    if after.text == context.text, restore(context) { return false }
                    return true
                }
            }
        }
        let posted: Bool
        if let pasteOverride {
            posted = pasteOverride(insertedText, selected, expectedText)
        } else {
            let expectedPrefix = (context.text as NSString).substring(to: range.location) + insertedText
            posted = ClipboardPaste.shared.paste(insertedText, into: context.element, marker: Self.syntheticEventMarker,
                validate: { !self.secureInput() && self.readContext()?.matches(selected) == true },
                applied: {
                    guard let after = self.readContext(), CFEqual(after.element, context.element) else { return false }
                    return after.text == expectedText || (after.range.length == 0 && after.prefix.hasPrefix(expectedPrefix))
                },
                completion: { [logger] verified in
                    logger.info("Paste replacement verified=\(verified)")
                    if verified { completion() }
                })
        }
        if posted { return true }
        return !restore(context)
    }

    private func confirmSelection(_ context: TextReplacementContext, range: CFRange) -> TextReplacementContext? {
        for attempt in 0..<8 {
            guard let selected = readContext(), CFEqual(selected.element, context.element), selected.text == context.text else { return nil }
            if selected.range.location == range.location && selected.range.length == range.length { return selected }
            guard selected.matches(context), attempt < 7 else { return nil }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return nil
    }

    private func restore(_ context: TextReplacementContext) -> Bool {
        guard let now = readContext(), CFEqual(now.element, context.element), now.text == context.text else { return false }
        var previous = context.range
        guard let value = AXValueCreate(.cfRange, &previous),
              access.set(context.element, kAXSelectedTextRangeAttribute, value) == .success,
              readContext()?.matches(context) == true else { return false }
        return true
    }

    static func wasIgnored(before: String, expected: String, after: String?) -> Bool {
        before != expected && after == before
    }

    static func inlineDelimiter(_ event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0, length <= buffer.count else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }
            ? text : nil
    }
}
