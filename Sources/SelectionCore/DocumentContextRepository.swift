import CryptoKit
import Foundation

/// Per-account document context. Kept outside AppSettings so a long article
/// does not get re-encoded every time a toggle changes.
///
/// The context file is encrypted with AES-GCM. The 256-bit key lives in the
/// app's Keychain item, not in Application Support. Old plaintext `.txt` files
/// are migrated on the first read so existing users keep their context.
enum DocumentContextRepository {
    static let maxStoredCharacters = 20_000

    /// Test seam. Production uses the Keychain item.
    static var directoryOverride: URL?
    static var keyOverride: Data?

    private static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SelectionTranslator", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func fileURL(accountID: UUID) -> URL {
        directory.appendingPathComponent("document-context-\(accountID.uuidString).enc")
    }

    static func legacyFileURL(accountID: UUID) -> URL {
        directory.appendingPathComponent("document-context-\(accountID.uuidString).txt")
    }

    static func read(accountID: UUID) -> String {
        if let data = try? Data(contentsOf: fileURL(accountID: accountID)),
           let text = decrypt(data) {
            return String(text.prefix(maxStoredCharacters))
        }

        guard let data = try? Data(contentsOf: legacyFileURL(accountID: accountID)),
              let text = String(data: data, encoding: .utf8) else { return "" }
        write(text, accountID: accountID)
        try? FileManager.default.removeItem(at: legacyFileURL(accountID: accountID))
        return String(text.prefix(maxStoredCharacters))
    }

    static func write(_ text: String, accountID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed.prefix(maxStoredCharacters))
        guard !value.isEmpty else {
            clear(accountID: accountID)
            return
        }
        guard let encrypted = encrypt(value) else {
            // Do not delete an existing context when the Keychain is
            // temporarily unavailable or the user denies access.
            return
        }
        do {
            try encrypted.write(to: fileURL(accountID: accountID), options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL(accountID: accountID).path
            )
        } catch {
            // Keep the repository non-throwing for the settings UI; a failed
            // write is equivalent to clearing the context for this session.
        }
    }

    static func clear(accountID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(accountID: accountID))
        try? FileManager.default.removeItem(at: legacyFileURL(accountID: accountID))
    }

    private static func encryptionKey() -> SymmetricKey? {
        if let keyOverride {
            return keyOverride.count == 32 ? SymmetricKey(data: keyOverride) : nil
        }
        let account = "documentContextKey"
        switch KeychainStore.readResult(key: account) {
        case .found(let stored):
            guard let data = Data(base64Encoded: stored), data.count == 32 else {
                // A corrupt existing key should not be silently replaced:
                // doing so would make existing encrypted contexts unreadable.
                return nil
            }
            return SymmetricKey(data: data)
        case .failed:
            return nil
        case .missing:
            let key = SymmetricKey(size: .bits256)
            let raw = key.withUnsafeBytes { Data($0) }
            guard KeychainStore.save(raw.base64EncodedString(), key: account) else {
                return nil
            }
            return key
        }
    }

    private static func encrypt(_ text: String) -> Data? {
        guard let key = encryptionKey(),
              let sealed = try? AES.GCM.seal(Data(text.utf8), using: key) else {
            return nil
        }
        return sealed.combined
    }

    private static func decrypt(_ data: Data) -> String? {
        guard let key = encryptionKey(),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key) else {
            return nil
        }
        return String(data: opened, encoding: .utf8)
    }
}
