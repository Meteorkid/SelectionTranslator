import Foundation
import Security

enum KeychainStore {
    private static let service = "com.meteor.SelectionTranslator"

    enum ReadResult {
        case found(String)
        case missing
        case failed
    }

    @discardableResult
    static func save(_ value: String, key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if value.isEmpty {
            // Empty means "remove this secret"; do not leave a stale item.
            let deleteStatus = SecItemDelete(query as CFDictionary)
            return deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
        }

        // Update in place first. Deleting before an add is risky: a failed
        // add would lose the previous key that is still needed by the app.
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func readResult(key: String) -> ReadResult {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return .failed
            }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        default:
            return .failed
        }
    }

    static func read(key: String) -> String? {
        if case .found(let value) = readResult(key: key) {
            return value
        }
        return nil
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
