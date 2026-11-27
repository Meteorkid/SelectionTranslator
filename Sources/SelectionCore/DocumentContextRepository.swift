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
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        return root
    }

    static func fileURL(accountID: UUID) -> URL {
        directory.appendingPathComponent("document-context-\(accountID.uuidString).enc")
    }

    static func legacyFileURL(accountID: UUID) -> URL {
        directory.appendingPathComponent("document-context-\(accountID.uuidString).txt")
    }

    enum LoadResult: Equatable {
        case loaded(String)
        case empty
        case unavailable
    }

    /// A plain string is enough for translation paths. The settings UI uses
    /// `loadResult` so a Keychain denial cannot look like "the user cleared
    /// the context" and trigger an auto-save that deletes the encrypted file.
    static func read(accountID: UUID) -> String {
        switch loadResult(accountID: accountID) {
        case .loaded(let text):
            return text
        case .empty, .unavailable:
            return ""
        }
    }

    static func loadResult(accountID: UUID) -> LoadResult {
        if let data = try? Data(contentsOf: fileURL(accountID: accountID)) {
            guard let text = decrypt(data) else {
                return .unavailable
            }
            return .loaded(String(text.prefix(maxStoredCharacters)))
        }

        guard let data = try? Data(contentsOf: legacyFileURL(accountID: accountID)),
              let text = String(data: data, encoding: .utf8) else { return .empty }
        write(text, accountID: accountID)
        if FileManager.default.fileExists(atPath: fileURL(accountID: accountID).path) {
            try? FileManager.default.removeItem(at: legacyFileURL(accountID: accountID))
        }
        return .loaded(String(text.prefix(maxStoredCharacters)))
    }

    @discardableResult
    static func write(_ text: String, accountID: UUID) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed.prefix(maxStoredCharacters))
        guard !value.isEmpty else {
            clear(accountID: accountID)
            return true
        }
        guard let encrypted = encrypt(value) else {
            // Do not delete an existing context when the Keychain is
            // temporarily unavailable or the user denies access.
            return false
        }
        do {
            try encrypted.write(to: fileURL(accountID: accountID), options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL(accountID: accountID).path
            )
            return true
        } catch {
            return false
        }
    }

    static func clear(accountID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(accountID: accountID))
        try? FileManager.default.removeItem(at: legacyFileURL(accountID: accountID))
    }

    private static let keyLock = NSLock()
    private static var cachedKey: SymmetricKey?

    private static func encryptionKey() -> SymmetricKey? {
        if let keyOverride {
            return keyOverride.count == 32 ? SymmetricKey(data: keyOverride) : nil
        }

        // The context is encrypted on every settings edit and decrypted on
        // every translation. Reading the same Keychain item synchronously each
        // time is unnecessary and can make typing/selection feel sticky.
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }

        let account = "documentContextKey"
        switch KeychainStore.readResult(key: account) {
        case .found(let stored):
            guard let data = Data(base64Encoded: stored), data.count == 32 else {
                // A corrupt existing key should not be silently replaced:
                // doing so would make existing encrypted contexts unreadable.
                return nil
            }
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        case .failed:
            return nil
        case .missing:
            let key = SymmetricKey(size: .bits256)
            let raw = key.withUnsafeBytes { Data($0) }
            guard KeychainStore.save(raw.base64EncodedString(), key: account) else {
                return nil
            }
            cachedKey = key
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
