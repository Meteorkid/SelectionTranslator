import CoreGraphics
import Foundation

/// One Vision observation, normalized to the image's top-left origin.
struct RecognizedLine: Equatable {
    let text: String
    let frame: CGRect
}

/// Rebuilds reading order and paragraph breaks from Vision's line boxes.
///
/// Vision returns separate observations for columns and fragments on the same
/// visual row. Sorting every box by its center is not enough: it can split a
/// row into multiple output lines and flatten real paragraph gaps. This layout
/// groups same-row fragments, reads them left to right, then inserts one
/// newline per line and a blank line for a paragraph-sized vertical gap.
enum OCRTextLayout {
    static func text(from lines: [RecognizedLine]) -> String? {
        let lines = lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !lines.isEmpty else { return nil }

        if let split = twoColumnSplit(in: lines) {
            return columnAwareText(lines: lines, split: split)
        }
        return layoutText(from: lines)
    }

    /// Flattens already-ordered lines into paragraphs. Column detection is
    /// intentionally not recursive here: callers pass a single column (or a
    /// normal one-column page), so a second split would be a table/figure.
    private static func layoutText(from lines: [RecognizedLine]) -> String? {
        guard !lines.isEmpty else { return nil }
        let rows = rows(of: lines)
        guard let first = rows.first else { return nil }

        let heights = rows.map(\.frame.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let paragraphGap = max(0.03, medianHeight * 1.7)
        let lineGap = max(0.012, medianHeight * 0.8)
        let rightEdge = rows.map(\.frame.maxX).max() ?? first.frame.maxX

        var output = first.text
        for (previous, row) in zip(rows, rows.dropFirst()) {
            let gap = row.frame.minY - previous.frame.maxY
            if gap > paragraphGap {
                output += "\n\n" + row.text
            } else if gap > lineGap
                || startsListItem(row.text)
                || hasRoom(for: row, after: previous, rightEdge: rightEdge) {
                output += "\n" + row.text
            } else {
                output = joinWrapped(output, row.text)
            }
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct ColumnSplit {
        let gutterStart: CGFloat
        let gutterEnd: CGFloat
        let left: [RecognizedLine]
        let right: [RecognizedLine]
        let fullWidth: [RecognizedLine]
    }

    /// Detect an article-style two-column layout from the empty vertical
    /// gutter. Full-width titles/footers are excluded from gutter detection
    /// and placed back as horizontal separators. Requiring at least three
    /// lines per side avoids turning a single row of two fragments (or a
    /// three-line caption) into a column boundary.
    private static func twoColumnSplit(in lines: [RecognizedLine]) -> ColumnSplit? {
        guard lines.count >= 6 else { return nil }
        let minX = lines.map(\.frame.minX).min() ?? 0
        let maxX = lines.map(\.frame.maxX).max() ?? 0
        let pageWidth = maxX - minX
        guard pageWidth > 0.05 else { return nil }

        // Lines wider than 60% of the page are headers, footers or
        // full-width figures; they must not close the gutter used to detect
        // the columns.
        let narrow = lines.filter { $0.frame.width <= pageWidth * 0.60 }
        guard narrow.count >= 6 else { return nil }

        var intervals = narrow.map { (start: $0.frame.minX, end: $0.frame.maxX) }
            .sorted { $0.start < $1.start }
        var merged: [(start: CGFloat, end: CGFloat)] = []
        for interval in intervals {
            if let last = merged.last, interval.start <= last.end + 0.002 {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        intervals.removeAll(keepingCapacity: false)

        var best: (start: CGFloat, end: CGFloat)?
        for (left, right) in zip(merged, merged.dropFirst()) {
            let width = right.start - left.end
            if width >= max(0.012, pageWidth * 0.03),
               width > (best.map { $0.end - $0.start } ?? 0) {
                best = (left.end, right.start)
            }
        }
        guard let gap = best else { return nil }

        let tolerance: CGFloat = 0.004
        let left = lines.filter { $0.frame.maxX <= gap.start + tolerance }
        let right = lines.filter { $0.frame.minX >= gap.end - tolerance }
        let full = lines.filter {
            $0.frame.maxX > gap.start + tolerance && $0.frame.minX < gap.end - tolerance
        }
        guard left.count >= 3, right.count >= 3 else { return nil }
        guard left.map(\.frame.minX).max() ?? 0 < gap.start,
              right.map(\.frame.maxX).min() ?? 1 > gap.end else {
            return nil
        }
        return ColumnSplit(
            gutterStart: gap.start,
            gutterEnd: gap.end,
            left: left,
            right: right,
            fullWidth: full
        )
    }

    private static func columnAwareText(
        lines: [RecognizedLine],
        split: ColumnSplit
    ) -> String? {
        let separators = split.fullWidth.sorted { $0.frame.midY < $1.frame.midY }

        let tolerance: CGFloat = 0.004
        func isLeft(_ line: RecognizedLine) -> Bool {
            line.frame.maxX <= split.gutterStart + tolerance
        }
        func isRight(_ line: RecognizedLine) -> Bool {
            line.frame.minX >= split.gutterEnd - tolerance
        }
        func segmentText(_ segment: [RecognizedLine]) -> String? {
            let left = segment.filter(isLeft)
            let right = segment.filter(isRight)
            let full = segment.filter { !isLeft($0) && !isRight($0) }
            guard !left.isEmpty || !right.isEmpty || !full.isEmpty else { return nil }
            if left.isEmpty || right.isEmpty {
                return layoutText(from: segment)
            }
            let leftText = layoutText(from: left)
            let rightText = layoutText(from: right)
            let fullText = layoutText(from: full)
            return [fullText, leftText, rightText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        var blocks: [String] = []
        var pending = lines
        for separator in separators {
            let before = pending.filter { $0.frame.midY < separator.frame.minY }
            if let text = segmentText(before), !text.isEmpty {
                blocks.append(text)
            }
            pending.removeAll { line in
                line == separator || line.frame.midY < separator.frame.minY
            }
            if let text = layoutText(from: [separator]), !text.isEmpty {
                blocks.append(text)
            }
        }
        if let text = segmentText(pending), !text.isEmpty {
            blocks.append(text)
        }
        let result = blocks.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// A wrapped line only ends early when the next word does not fit, so
    /// room for that word plus slack means the line was broken on purpose.
    /// Widths are estimated from the previous row's average character width.
    private static func hasRoom(
        for row: Row,
        after previous: Row,
        rightEdge: CGFloat
    ) -> Bool {
        let characterWidth = previous.frame.width / CGFloat(max(previous.text.count, 1))
        let room = rightEdge - previous.frame.maxX
        let firstWord: Int
        if let first = row.text.first, first.isCJKIdeograph {
            firstWord = 1
        } else {
            firstWord = row.text.prefix { !$0.isWhitespace }.count
        }
        return room > characterWidth * (CGFloat(firstWord) * 1.4 + 1)
    }

    private static func startsListItem(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        if "•◦▪▫‣∙·●○■□▸►".contains(first) {
            return true
        }
        let rest = text.dropFirst()
        if "-*+".contains(first) {
            return rest.first == " "
        }
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count) else { return false }
        let marker = text.dropFirst(digits.count)
        if marker.first == "、" {
            return true
        }
        return (marker.first == "." || marker.first == ")")
            && marker.dropFirst().first == " "
    }

    /// CJK wraps without spaces; Latin wraps at a space or a hyphen.
    private static func joinWrapped(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else {
            return head + tail
        }
        if last.isCJKIdeograph || first.isCJKIdeograph {
            return head + tail
        }
        if last == "-", head.dropLast().last?.isLetter == true, first.isLowercase {
            return String(head.dropLast()) + tail
        }
        return head + " " + tail
    }

    private struct Row {
        var text: String
        var frame: CGRect
    }

    private static func rows(of lines: [RecognizedLine]) -> [Row] {
        // Vision's coordinate space has a bottom-left origin; the caller
        // already normalized these frames to top-left coordinates.
        let sorted = lines.sorted {
            if abs($0.frame.midY - $1.frame.midY) > 0.005 {
                return $0.frame.midY < $1.frame.midY
            }
            return $0.frame.minX < $1.frame.minX
        }

        var groups: [[RecognizedLine]] = []
        for line in sorted {
            if let last = groups.last?.last,
               abs(line.frame.midY - last.frame.midY) < min(line.frame.height, last.frame.height) * 0.5 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }

        return groups.map { group in
            let ordered = group.sorted { $0.frame.minX < $1.frame.minX }
            let text = ordered.map {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }.joined(separator: " ")
            let frame = ordered.dropFirst().reduce(ordered[0].frame) {
                $0.union($1.frame)
            }
            return Row(text: text, frame: frame)
        }
    }
}


private extension Character {
    var isCJKIdeograph: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xF900...0xFAFF, 0xFF00...0xFFEF:
                true
            default:
                false
            }
        }
    }
}
