import Foundation

/// Per-account document context. Kept outside AppSettings so a long article
/// does not get re-encoded every time a toggle changes.
enum DocumentContextRepository {
    static let maxStoredCharacters = 20_000

    private static var directory: URL {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SelectionTranslator", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func fileURL(accountID: UUID) -> URL {
        directory.appendingPathComponent("document-context-\(accountID.uuidString).txt")
    }

    static func read(accountID: UUID) -> String {
        guard let data = try? Data(contentsOf: fileURL(accountID: accountID)),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(maxStoredCharacters))
    }

    static func write(_ text: String, accountID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed.prefix(maxStoredCharacters))
        try? value.write(to: fileURL(accountID: accountID), atomically: true, encoding: .utf8)
    }

    static func clear(accountID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(accountID: accountID))
    }
}
