import Foundation
import ApplicationServices

enum ContextExtractor {
    static func context(around range: CFRange, in element: AXUIElement, maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }

        if let fullText = AX.fullText(of: element),
           (fullText as NSString).length >= range.location + range.length {
            return substring(fullText, around: range, maxLength: maxLength)
        }

        let half = maxLength / 2
        let start = max(0, range.location - half)
        let length = maxLength + max(0, range.length)
        if let chunk = AX.string(for: CFRange(location: start, length: length), in: element) {
            // The fallback range includes the selection length; cap the
            // returned context so the user's context setting remains an
            // upper bound even when the app exposes no full text value.
            return String(chunk.prefix(maxLength))
        }
        return ""
    }

    static func substring(_ text: String, around range: CFRange, maxLength: Int) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return "" }

        let selectionStart = min(max(0, range.location), nsText.length)
        let selectionLength = max(0, min(range.length, nsText.length - selectionStart))
        let half = maxLength / 2

        var start = max(0, selectionStart - half)
        var end = min(nsText.length, selectionStart + selectionLength + half)

        if selectionLength > 0 {
            let paragraph = nsText.paragraphRange(for: NSRange(location: selectionStart, length: selectionLength))
            start = min(start, paragraph.location)
            end = max(end, paragraph.location + paragraph.length)
        }

        if end - start > maxLength {
            let center = selectionStart + selectionLength / 2
            start = max(0, center - maxLength / 2)
            end = min(nsText.length, start + maxLength)
        }

        return nsText.substring(with: NSRange(location: start, length: end - start))
    }
}
