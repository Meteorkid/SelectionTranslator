import Foundation
import CoreServices

/// Thin wrapper around macOS Dictionary Services.
/// This is the same system dictionary users already have in Dictionary.app.
enum AppleDictionaryService {
    static func lookup(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return nil }

        let nsWord = trimmed as NSString
        guard let definition = DCSCopyTextDefinition(
            nil,
            nsWord as CFString,
            CFRange(location: 0, length: nsWord.length)
        )?.takeRetainedValue() as String? else {
            return nil
        }

        let cleaned = definition
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(2_400))
    }
}
