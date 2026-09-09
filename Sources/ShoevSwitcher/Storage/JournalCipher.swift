import CryptoKit
import Foundation

enum JournalCipherError: Error {
    case invalidKey
    case invalidText
}

final class JournalCipher {
    private static let keyFileName = ".journal-key"

    private let key: SymmetricKey

    init(directory: URL) throws {
        let keyURL = directory.appendingPathComponent(Self.keyFileName, isDirectory: false)
        let data: Data

        if FileManager.default.fileExists(atPath: keyURL.path) {
            data = try Data(contentsOf: keyURL)
        } else {
            let generated = SymmetricKey(size: .bits256)
            data = generated.withUnsafeBytes { Data($0) }
            try data.write(to: keyURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: keyURL.path
            )
        }

        guard data.count == 32 else { throw JournalCipherError.invalidKey }
        key = SymmetricKey(data: data)
    }

    func encrypt(_ text: String) throws -> Data {
        let sealed = try AES.GCM.seal(Data(text.utf8), using: key)
        guard let combined = sealed.combined else { throw JournalCipherError.invalidText }
        return combined
    }

    func decrypt(_ data: Data) throws -> String {
        let box = try AES.GCM.SealedBox(combined: data)
        let clear = try AES.GCM.open(box, using: key)
        guard let text = String(data: clear, encoding: .utf8) else {
            throw JournalCipherError.invalidText
        }
        return text
    }

}
