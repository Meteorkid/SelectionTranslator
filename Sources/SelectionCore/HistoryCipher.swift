import CryptoKit
import Foundation

enum HistoryCipherError: LocalizedError {
    case keyUnavailable
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .keyUnavailable:
            return "历史加密密钥不可用；请检查钥匙串访问权限。"
        case .malformed(let field):
            return "历史字段无法解密：\(field)"
        }
    }
}

/// Field-level encryption for translation history. Only the fields that
/// reveal what the user read are encrypted; account ID, timestamps, language,
/// engine and favorite are kept queryable. A prefix marks each encrypted
/// value so rows written by older versions remain readable and can be migrated
/// in place.
struct HistoryCipher {
    static let prefix = "enc:v1:"
    private let key: SymmetricKey?

    init(keyOverride: Data? = nil) {
        if let keyOverride, keyOverride.count == 32 {
            key = SymmetricKey(data: keyOverride)
            return
        }
        key = Self.loadOrCreateKey()
    }

    var isAvailable: Bool { key != nil }

    static func isEncrypted(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }

    func encrypt(_ value: String) throws -> String {
        guard !value.isEmpty else { return "" }
        guard let key else { throw HistoryCipherError.keyUnavailable }
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: key),
              let combined = sealed.combined else {
            throw HistoryCipherError.malformed("encrypt")
        }
        return Self.prefix + combined.base64EncodedString()
    }

    func decrypt(_ value: String) throws -> String {
        guard Self.isEncrypted(value) else { return value }
        guard let key else { throw HistoryCipherError.keyUnavailable }
        let encoded = String(value.dropFirst(Self.prefix.count))
        guard let data = Data(base64Encoded: encoded),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key),
              let text = String(data: opened, encoding: .utf8) else {
            throw HistoryCipherError.malformed(value.prefix(24) + "…")
        }
        return text
    }

    private static func loadOrCreateKey() -> SymmetricKey? {
        let account = "historyEncryptionKey"
        switch KeychainStore.readResult(key: account) {
        case .found(let stored):
            guard let data = Data(base64Encoded: stored), data.count == 32 else {
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
}
