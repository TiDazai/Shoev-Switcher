import Carbon.HIToolbox
import Foundation

final class InputSourceManager {
    struct Source {
        let reference: TISInputSource
        let identifier: String
        let name: String
        let languages: [String]

        var primaryLanguage: InputLanguage? {
            if languages.contains(where: { $0.lowercased().hasPrefix("ru") }) {
                return .russian
            }
            if languages.contains(where: { $0.lowercased().hasPrefix("en") }) {
                return .english
            }
            return nil
        }
    }

    private let defaults: UserDefaults
    private(set) var englishSource: Source?
    private(set) var russianSource: Source?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reloadSources()
    }

    func reloadSources() {
        let sources = enabledKeyboardSources()
        englishSource = preferredSource(
            language: .english,
            savedIdentifier: defaults.string(forKey: PreferenceKey.englishInputSource),
            sources: sources
        )
        russianSource = preferredSource(
            language: .russian,
            savedIdentifier: defaults.string(forKey: PreferenceKey.russianInputSource),
            sources: sources
        )

        if let englishSource {
            defaults.set(englishSource.identifier, forKey: PreferenceKey.englishInputSource)
        }
        if let russianSource {
            defaults.set(russianSource.identifier, forKey: PreferenceKey.russianInputSource)
        }
    }

    func currentLanguage() -> InputLanguage? {
        guard let unmanaged = TISCopyCurrentKeyboardLayoutInputSource() else { return nil }
        return makeSource(unmanaged.takeRetainedValue()).primaryLanguage
    }

    func source(for language: InputLanguage) -> Source? {
        switch language {
        case .english: return englishSource
        case .russian: return russianSource
        }
    }

    @discardableResult
    func select(_ language: InputLanguage) -> Bool {
        guard let source = source(for: language) else { return false }
        return TISSelectInputSource(source.reference) == noErr
    }

    func text(for strokes: [KeyStroke], in language: InputLanguage) -> String? {
        guard let source = source(for: language) else { return nil }
        return strokes.map { stroke in
            let translated = translatedCharacter(keyCode: stroke.keyCode, source: source) ?? fallbackCharacter(
                visibleText: stroke.visibleText,
                targetLanguage: language
            )
            return applyingCasePattern(from: stroke, to: translated)
        }.joined()
    }

    func isPotentialWordStroke(_ stroke: KeyStroke) -> Bool {
        InputLanguage.allCases.contains { language in
            guard let text = text(for: [stroke], in: language), !text.isEmpty else { return false }
            return text.unicodeScalars.allSatisfy { scalar in
                CharacterSet.letters.contains(scalar) || scalar == "'" || scalar == "-"
            }
        }
    }

    func convertedText(
        _ text: String,
        from sourceLanguage: InputLanguage,
        to targetLanguage: InputLanguage
    ) -> String {
        guard sourceLanguage != targetLanguage else { return text }
        let from = sourceLanguage == .english ? Self.englishCharacters : Self.russianCharacters
        let to = targetLanguage == .russian ? Self.russianCharacters : Self.englishCharacters
        return text.map { character in
            let lower = Character(String(character).lowercased())
            guard let index = from.firstIndex(of: lower) else { return String(character) }
            let offset = from.distance(from: from.startIndex, to: index)
            guard let targetIndex = to.index(to.startIndex, offsetBy: offset, limitedBy: to.endIndex),
                  targetIndex < to.endIndex else { return String(character) }
            let translated = String(to[targetIndex])
            let original = String(character)
            return original == original.uppercased() && original != original.lowercased()
                ? translated.uppercased()
                : translated
        }.joined()
    }

    func allSources(for language: InputLanguage) -> [Source] {
        enabledKeyboardSources().filter { $0.primaryLanguage == language }
    }

    private func preferredSource(
        language: InputLanguage,
        savedIdentifier: String?,
        sources: [Source]
    ) -> Source? {
        let matching = sources.filter { $0.primaryLanguage == language }
        if let savedIdentifier,
           let saved = matching.first(where: { $0.identifier == savedIdentifier }) {
            return saved
        }

        let preferredIdentifiers: [String]
        switch language {
        case .english:
            preferredIdentifiers = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        case .russian:
            preferredIdentifiers = ["com.apple.keylayout.RussianWin", "com.apple.keylayout.Russian"]
        }

        for identifier in preferredIdentifiers {
            if let preferred = matching.first(where: { $0.identifier == identifier }) {
                return preferred
            }
        }
        return matching.first
    }

    private func enabledKeyboardSources() -> [Source] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsEnabled: kCFBooleanTrue as Any,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue as Any
        ]
        guard let unmanaged = TISCreateInputSourceList(filter as CFDictionary, false) else {
            return []
        }
        let values = unmanaged.takeRetainedValue() as NSArray
        let sources = values as? [TISInputSource] ?? []
        return sources.map(makeSource)
    }

    private func makeSource(_ reference: TISInputSource) -> Source {
        Source(
            reference: reference,
            identifier: stringProperty(reference, key: kTISPropertyInputSourceID) ?? "",
            name: stringProperty(reference, key: kTISPropertyLocalizedName) ?? "",
            languages: arrayProperty(reference, key: kTISPropertyInputSourceLanguages) ?? []
        )
    }

    private func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func arrayProperty(_ source: TISInputSource, key: CFString) -> [String]? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
    }

    private func translatedCharacter(keyCode: CGKeyCode, source: Source) -> String? {
        guard let pointer = TISGetInputSourceProperty(source.reference, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0

        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else { return OSStatus(paramErr) }
            let layout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    private func fallbackCharacter(visibleText: String, targetLanguage: InputLanguage) -> String {
        let english = Self.englishCharacters
        let russian = Self.russianCharacters
        let from = targetLanguage == .russian ? english : russian
        let to = targetLanguage == .russian ? russian : english
        let lowercased = visibleText.lowercased()
        guard lowercased.count == 1,
              let character = lowercased.first,
              let index = from.firstIndex(of: character) else {
            return visibleText
        }
        let offset = from.distance(from: from.startIndex, to: index)
        guard let targetIndex = to.index(to.startIndex, offsetBy: offset, limitedBy: to.endIndex),
              targetIndex < to.endIndex else {
            return visibleText
        }
        return String(to[targetIndex])
    }

    private func applyingCasePattern(from stroke: KeyStroke, to translated: String) -> String {
        let originalIsUppercase = stroke.visibleText != stroke.visibleText.lowercased()
            && stroke.visibleText == stroke.visibleText.uppercased()
        guard stroke.shouldUppercase || originalIsUppercase else {
            return translated
        }
        return translated.uppercased()
    }

    private static let englishCharacters = "`qwertyuiop[]\\asdfghjkl;'zxcvbnm,./"
    private static let russianCharacters = "ёйцукенгшщзхъ\\фывапролджэячсмитьбю."
}
