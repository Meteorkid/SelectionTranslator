import Foundation

/// Comparable quality signal for one Vision OCR pass.
///
/// Vision can return a short, high-confidence fragment from a low-contrast
/// screenshot. Counting only confidence would prefer that fragment over a
/// larger, slightly less certain pass, so the score also rewards the number of
/// recognized characters and lines.
struct OCRQuality: Equatable {
    let text: String
    let averageConfidence: Double
    let characterCount: Int
    let lineCount: Int

    init(text: String, averageConfidence: Double, lineCount: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmed
        self.averageConfidence = min(max(averageConfidence, 0), 1)
        self.characterCount = trimmed.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }.count
        self.lineCount = max(lineCount, 0)
    }

    var isReliable: Bool {
        characterCount >= 2 && averageConfidence >= 0.52
    }

    var score: Double {
        averageConfidence * 100
            + log(Double(max(characterCount, 1))) * 9
            + Double(min(lineCount, 20)) * 0.4
    }
}
