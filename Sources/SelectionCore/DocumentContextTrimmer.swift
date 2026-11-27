import Foundation

/// Keeps a long document useful without blindly truncating its head.
/// Prefer a window around the first occurrence of the selection; fall back to
/// the beginning when the selection cannot be located (for example, an OCR
/// result that is not verbatim in the source document).
enum DocumentContextTrimmer {
    static func trim(
        _ document: String,
        maxCharacters: Int,
        selection: String
    ) -> String {
        let text = document.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxCharacters > 0 else { return "" }
        guard text.count > maxCharacters else {
            return text
        }

        let needle = String(selection.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        if !needle.isEmpty,
           let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            let headRoom = maxCharacters / 3
            let lower = text.index(
                range.lowerBound,
                offsetBy: -min(headRoom, text.distance(from: text.startIndex, to: range.lowerBound))
            )
            let upper = text.index(
                lower,
                offsetBy: min(maxCharacters, text.distance(from: lower, to: text.endIndex))
            )
            return lineClipped(String(text[lower..<upper]), maxCharacters: maxCharacters)
        }

        let prefix = String(text.prefix(maxCharacters))
        return lineClipped(prefix, maxCharacters: maxCharacters)
    }

    private static func lineClipped(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let clipped = String(text.prefix(maxCharacters))
        guard let newline = clipped.lastIndex(of: "\n"),
              clipped.distance(from: clipped.startIndex, to: newline) > maxCharacters / 2 else {
            return clipped
        }
        return String(clipped[..<newline])
    }
}
