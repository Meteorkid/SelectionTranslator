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

        let rows = rows(of: lines)
        guard let first = rows.first else { return nil }

        let heights = rows.map(\.frame.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let paragraphGap = max(0.03, medianHeight * 1.7)

        var output = first.text
        for (previous, row) in zip(rows, rows.dropFirst()) {
            let gap = row.frame.minY - previous.frame.maxY
            output += gap > paragraphGap ? "\n\n" : "\n"
            output += row.text
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
