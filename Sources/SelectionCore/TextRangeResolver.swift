import Foundation

/// Finds the UTF-16 range of selected text inside a larger accessible document.
///
/// Some WebKit/Chromium trees expose a selection only through an AX text-marker
/// range, without `AXSelectedTextRange`. Searching the full marker text for the
/// selected string lets context extraction keep working in that case.
enum TextRangeResolver {
    static func firstRange(of needle: String, in haystack: String) -> NSRange? {
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        let range = (haystack as NSString).range(of: needle)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return range
    }
}
