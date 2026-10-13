import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

protocol TextReplacing {
    func replace(original: String, with replacement: String, trailingEvent: CGEvent?, context: TextReplacementContext) -> Bool
    func replaceAfterDelimiter(original: String, with replacement: String, trailingEvent: CGEvent,
                               context: TextReplacementContext, completion: @escaping () -> Void) -> Bool
    func replaceConfirmed(original: String, with replacement: String, preservingDelimiter: String,
                          context: TextReplacementContext, completion: @escaping () -> Void) -> Bool
}
extension TextReplacing {
    func replaceConfirmed(original: String, with replacement: String, preservingDelimiter: String,
                          context: TextReplacementContext, completion: @escaping () -> Void) -> Bool {
        let accepted = replace(original: original + preservingDelimiter, with: replacement + preservingDelimiter,
            trailingEvent: nil, context: context)
        if accepted { completion() }
        return accepted
    }
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
    private let normalizesCaseAfterDelimiter: (AXUIElement) -> Bool
    private let logger = Logger(subsystem: "com.shoev.switcher", category: "replacement")
    private var generation = 0
    func cancelPending() { generation &+= 1 }

    init(access: AccessibilityAccess = AccessibilityAccess(),
         readContext: @escaping () -> TextReplacementContext? = { TextReplacementContextReader().read() },
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
        pasteOverride: ((String, TextReplacementContext, String) -> Bool)? = nil,
        normalizesCaseAfterDelimiter: @escaping (AXUIElement) -> Bool = { element in
            var pid: pid_t = 0
            return AXUIElementGetPid(element, &pid) == .success
                && NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.microsoft.Word"
        }) {
        self.access = access
        self.readContext = readContext
        self.secureInput = secureInput
        self.pasteOverride = pasteOverride
        self.normalizesCaseAfterDelimiter = normalizesCaseAfterDelimiter
    }

    @discardableResult
    func replace(original: String, with replacement: String, trailingEvent: CGEvent? = nil, context: TextReplacementContext) -> Bool {
        perform(original: original, with: replacement, trailingEvent: trailingEvent, context: context)
    }

    func replaceAfterDelimiter(original: String, with replacement: String, trailingEvent: CGEvent,
                               context: TextReplacementContext, completion: @escaping () -> Void) -> Bool {
        guard let delimiter = Self.inlineDelimiter(trailingEvent), context.range.length == 0, !secureInput() else { return false }
        let mayNormalizeCase = normalizesCaseAfterDelimiter(context.element)
        var attempts = 0
        let scheduledGeneration = generation
        func attempt() {
            attempts += 1
            guard self.generation == scheduledGeneration, !self.secureInput(),
                  let now = self.readContext(), now.sameRegion(as: context) else { return }
            if let actual = Self.acknowledgedOriginal(context: context, after: now, original: original,
                delimiter: delimiter, allowingCaseNormalization: mayNormalizeCase) {
                // The physical delimiter already belongs to the editor. Never
                // select it: some text controls trim trailing space on AX/paste.
                _ = self.perform(original: actual, with: replacement,
                                 trailingEvent: nil, context: now,
                                 preservingDelimiter: delimiter, completion: completion)
            } else if now.matches(context), attempts < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: attempt)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: attempt)
        return false
    }

    /// Word can capitalize text as it handles the *physical* space. Accept only
    /// a same-length case-only normalization, never a native rewrite or further
    /// typing. The edit uses the fresh text and leaves all surrounding text intact.
    static func acknowledgedOriginal(context: TextReplacementContext, after: TextReplacementContext,
                                     original: String, delimiter: String, allowingCaseNormalization: Bool) -> String? {
        guard context.sameRegion(as: after), after.range.length == 0,
              after.range.location == context.range.location + delimiter.utf16.count else { return nil }
        let expected = (context.text as NSString).replacingCharacters(
            in: NSRange(location: context.range.location, length: 0), with: delimiter)
        if after.text == expected { return original }
        guard allowingCaseNormalization, after.text.utf16.count == expected.utf16.count,
              after.text.lowercased(with: Locale(identifier: "en_US_POSIX")) == expected.lowercased(with: Locale(identifier: "en_US_POSIX")),
              context.range.location >= original.utf16.count else { return nil }
        let actual = (after.text as NSString).substring(with: NSRange(location: context.range.location - original.utf16.count, length: original.utf16.count))
        guard actual.lowercased(with: Locale(identifier: "en_US_POSIX")) == original.lowercased(with: Locale(identifier: "en_US_POSIX")) else { return nil }
        return actual
    }

    func replaceConfirmed(original: String, with replacement: String, preservingDelimiter: String,
                          context: TextReplacementContext, completion: @escaping () -> Void) -> Bool {
        perform(original: original, with: replacement, context: context, preservingDelimiter: preservingDelimiter, completion: completion)
    }

    private func perform(original: String, with replacement: String, trailingEvent: CGEvent? = nil,
                         context: TextReplacementContext, preservingDelimiter: String = "",
                         completion: @escaping () -> Void = {}) -> Bool {
        let scheduledGeneration = generation
        let wordCaret = context.range.location - preservingDelimiter.utf16.count
        guard wordCaret >= 0, context.prefix.hasSuffix(preservingDelimiter) else { return false }
        let replacementRange = original.isEmpty && !preservingDelimiter.isEmpty
            ? CFRange(location: wordCaret, length: 0)
            : TextReplacementContext.replacementRange(in: context.text, caret: wordCaret, original: original)
        guard !secureInput(),
              context.range.length == 0,
              let range = replacementRange else { return false }
        let selection = AccessibilityTextSelection(access: access)
        guard selection.canSet(context) else { return false }
        let delimiter = trailingEvent.flatMap(Self.inlineDelimiter)
        guard trailingEvent == nil || delimiter != nil,
              readContext()?.matches(context) == true else { return false }
        guard selection.set(range, in: context) else { return false }
        let insertedText = replacement + (delimiter ?? "")
        guard let selected = confirmSelection(context, range: range) else { return !restore(context) }
        let expectedText = (context.text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: insertedText)
        let insertedRange = CFRange(location: range.location, length: insertedText.utf16.count)
        let finalCaret = range.location + insertedText.utf16.count + preservingDelimiter.utf16.count
        let expectedPrefix = (expectedText as NSString).substring(to: finalCaret)
        if access.writable(context.element, kAXSelectedTextAttribute) {
            guard readContext()?.matches(selected) == true else { return true }
            _ = access.set(context.element, kAXSelectedTextAttribute, insertedText as CFString)
            guard let after = readContext(), after.sameRegion(as: context) else { return true }
            if after.text == expectedText || (after.range.length == 0 && after.prefix.hasPrefix(expectedPrefix)) {
                finishReplacement(context: context, expectedText: expectedText,
                    insertedRange: insertedRange, finalCaret: finalCaret,
                    scheduledGeneration: scheduledGeneration, completion: completion)
                return true
            }
            // Only a verified no-op permits pasting over the same selection.
            if !after.matches(selected) {
                guard after.matches(context),
                      selection.set(range, in: context),
                      confirmSelection(context, range: range)?.matches(selected) == true else {
                    if after.text == context.text, restore(context) { return false }
                    return true
                }
            }
        }
        let posted: Bool
        if let pasteOverride {
            posted = pasteOverride(insertedText, selected, expectedText)
            if posted {
                finishReplacement(context: context, expectedText: expectedText,
                    insertedRange: insertedRange, finalCaret: finalCaret,
                    scheduledGeneration: scheduledGeneration, completion: completion)
            }
        } else {
            posted = ClipboardPaste.shared.paste(insertedText, into: context.element, marker: Self.syntheticEventMarker,
                validate: { !self.secureInput() && self.readContext()?.matches(selected) == true },
                applied: {
                    guard let after = self.readContext(), after.sameRegion(as: context) else { return false }
                    return after.text == expectedText || (after.range.length == 0 && after.prefix.hasPrefix(expectedPrefix))
                },
                completion: { [weak self] verified in
                    guard verified, let self else { return }
                    self.finishReplacement(context: context, expectedText: expectedText,
                        insertedRange: insertedRange, finalCaret: finalCaret,
                        scheduledGeneration: scheduledGeneration, completion: completion)
                })
        }
        if posted { return true }
        return !restore(context)
    }

    /// Replacing only the word leaves the editor's caret before the preserved
    /// delimiter. Move it past that delimiter and verify the AX setter; success
    /// alone is not proof. A renderer may apply the range on its next tick.
    private func finishReplacement(context: TextReplacementContext, expectedText: String,
                                   insertedRange: CFRange, finalCaret: Int,
                                   scheduledGeneration: Int,
                                   completion: @escaping () -> Void) {
        let expectedPrefix = (expectedText as NSString).substring(to: finalCaret)
        var attempts = 0
        func attempt() {
            attempts += 1
            guard self.generation == scheduledGeneration, !self.secureInput(),
                  let after = self.readContext(), after.sameRegion(as: context) else { return }
            // If typing has already continued after the delimiter, do not pull
            // the user's cursor back or replace any of the following text.
            if after.range.length == 0, after.range.location >= finalCaret,
               after.prefix.hasPrefix(expectedPrefix) {
                self.logger.info("Replacement and caret verified")
                completion()
                return
            }
            let atInsertedEnd = after.range.length == 0
                && after.range.location == insertedRange.location + insertedRange.length
            let insertedSelection = after.range.location == insertedRange.location
                && after.range.length == insertedRange.length
            guard after.text == expectedText, atInsertedEnd || insertedSelection else { return }
            let end = CFRange(location: finalCaret, length: 0)
            guard AccessibilityTextSelection(access: self.access).set(end, in: after) else { return }
            if let moved = self.readContext(), moved.sameRegion(as: context),
               moved.text == expectedText, moved.range.location == finalCaret, moved.range.length == 0 {
                self.logger.info("Replacement and caret verified")
                completion()
            } else if attempts < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: attempt)
            }
        }
        attempt()
    }

    private func confirmSelection(_ context: TextReplacementContext, range: CFRange) -> TextReplacementContext? {
        for attempt in 0..<8 {
            guard let selected = readContext(), selected.sameRegion(as: context), selected.text == context.text else { return nil }
            if selected.range.location == range.location && selected.range.length == range.length { return selected }
            guard selected.matches(context), attempt < 7 else { return nil }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return nil
    }

    private func restore(_ context: TextReplacementContext) -> Bool {
        guard let now = readContext(), now.sameRegion(as: context), now.text == context.text else { return false }
        guard AccessibilityTextSelection(access: access).set(context.range, in: context),
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
