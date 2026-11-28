import XCTest
@testable import SelectionTranslator

final class OCRTextLayoutTests: XCTestCase {
    func testSameRowFragmentsJoinLeftToRight() {
        let lines = [
            RecognizedLine(
                text: "world",
                frame: CGRect(x: 0.55, y: 0.00, width: 0.35, height: 0.05)
            ),
            RecognizedLine(
                text: "Hello",
                frame: CGRect(x: 0.05, y: 0.01, width: 0.40, height: 0.05)
            )
        ]

        XCTAssertEqual(OCRTextLayout.text(from: lines), "Hello world")
    }

    func testParagraphGapBecomesBlankLine() {
        let lines = [
            RecognizedLine(
                text: "First paragraph",
                frame: CGRect(x: 0.10, y: 0.00, width: 0.70, height: 0.04)
            ),
            RecognizedLine(
                text: "Second paragraph",
                frame: CGRect(x: 0.10, y: 0.13, width: 0.70, height: 0.04)
            )
        ]

        XCTAssertEqual(OCRTextLayout.text(from: lines), "First paragraph\n\nSecond paragraph")
    }

    func testTwoColumnArticleReadsLeftColumnBeforeRight() {
        var lines: [RecognizedLine] = [
            RecognizedLine(
                text: "Article title",
                frame: CGRect(x: 0.16, y: 0.00, width: 0.56, height: 0.04)
            )
        ]
        for index in 0..<3 {
            let y = 0.10 + CGFloat(index) * 0.08
            lines.append(RecognizedLine(
                text: "Left \(index + 1)",
                frame: CGRect(x: 0.05, y: y, width: 0.38, height: 0.04)
            ))
            lines.append(RecognizedLine(
                text: "Right \(index + 1)",
                frame: CGRect(x: 0.55, y: y, width: 0.38, height: 0.04)
            ))
        }
        lines.append(RecognizedLine(
            text: "Page footer",
            frame: CGRect(x: 0.10, y: 0.36, width: 0.80, height: 0.04)
        ))

        XCTAssertEqual(
            OCRTextLayout.text(from: lines),
            "Article title\n\nLeft 1\nLeft 2\nLeft 3\n\nRight 1\nRight 2\nRight 3\n\nPage footer"
        )
    }

    func testFullWidthSectionHeadingSplitsColumnSegments() {
        var lines: [RecognizedLine] = [
            RecognizedLine(
                text: "Article title",
                frame: CGRect(x: 0.16, y: 0.00, width: 0.56, height: 0.04)
            )
        ]
        for index in 0..<3 {
            let y = 0.10 + CGFloat(index) * 0.08
            lines.append(RecognizedLine(
                text: "Left \(index + 1)",
                frame: CGRect(x: 0.05, y: y, width: 0.38, height: 0.04)
            ))
            lines.append(RecognizedLine(
                text: "Right \(index + 1)",
                frame: CGRect(x: 0.55, y: y, width: 0.38, height: 0.04)
            ))
        }
        lines.append(RecognizedLine(
            text: "Section",
            frame: CGRect(x: 0.16, y: 0.30, width: 0.56, height: 0.04)
        ))
        for index in 0..<3 {
            let y = 0.36 + CGFloat(index) * 0.08
            lines.append(RecognizedLine(
                text: "Left \(index + 4)",
                frame: CGRect(x: 0.05, y: y, width: 0.38, height: 0.04)
            ))
            lines.append(RecognizedLine(
                text: "Right \(index + 4)",
                frame: CGRect(x: 0.55, y: y, width: 0.38, height: 0.04)
            ))
        }

        XCTAssertEqual(
            OCRTextLayout.text(from: lines),
            "Article title\n\nLeft 1\nLeft 2\nLeft 3\n\nRight 1\nRight 2\nRight 3\n\nSection\n\nLeft 4\nLeft 5\nLeft 6\n\nRight 4\nRight 5\nRight 6"
        )
    }

    func testTwoColumnsWithoutHeaderStayInReadingOrder() {
        var lines: [RecognizedLine] = []
        for index in 0..<3 {
            let y = 0.04 + CGFloat(index) * 0.08
            lines.append(RecognizedLine(
                text: "L\(index + 1)",
                frame: CGRect(x: 0.04, y: y, width: 0.40, height: 0.04)
            ))
            lines.append(RecognizedLine(
                text: "R\(index + 1)",
                frame: CGRect(x: 0.56, y: y, width: 0.40, height: 0.04)
            ))
        }

        XCTAssertEqual(OCRTextLayout.text(from: lines), "L1\nL2\nL3\n\nR1\nR2\nR3")
    }

    func testSingleColumnWithManyNarrowLinesIsNotSplit() {
        var lines: [RecognizedLine] = []
        for index in 0..<6 {
            lines.append(RecognizedLine(
                text: "Line \(index + 1)",
                frame: CGRect(x: 0.05, y: CGFloat(index) * 0.10, width: 0.38, height: 0.04)
            ))
        }

        XCTAssertEqual(
            OCRTextLayout.text(from: lines),
            "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6"
        )
    }

    func testOrdinaryLineGapUsesSingleNewline() {
        let lines = [
            RecognizedLine(
                text: "line one",
                frame: CGRect(x: 0.10, y: 0.00, width: 0.70, height: 0.04)
            ),
            RecognizedLine(
                text: "line two",
                frame: CGRect(x: 0.10, y: 0.09, width: 0.70, height: 0.04)
            )
        ]

        XCTAssertEqual(OCRTextLayout.text(from: lines), "line one\nline two")
    }

    func testWrappedLinesJoinIntoParagraph() {
        let lines = [
            RecognizedLine(
                text: "The quick brown fox",
                frame: CGRect(x: 0.04, y: 0.00, width: 0.80, height: 0.04)
            ),
            RecognizedLine(
                text: "jumps over the dog.",
                frame: CGRect(x: 0.04, y: 0.05, width: 0.55, height: 0.04)
            )
        ]

        XCTAssertEqual(
            OCRTextLayout.text(from: lines),
            "The quick brown fox jumps over the dog."
        )
    }

    func testListMarkerStartsNewLine() {
        let lines = [
            RecognizedLine(
                text: "Intro",
                frame: CGRect(x: 0.04, y: 0.00, width: 0.40, height: 0.04)
            ),
            RecognizedLine(
                text: "• First item",
                frame: CGRect(x: 0.04, y: 0.05, width: 0.40, height: 0.04)
            )
        ]

        XCTAssertEqual(OCRTextLayout.text(from: lines), "Intro\n• First item")
    }

    func testChineseWrappedLinesJoinWithoutSpace() {
        let lines = [
            RecognizedLine(
                text: "这是第一行",
                frame: CGRect(x: 0.04, y: 0.00, width: 0.80, height: 0.04)
            ),
            RecognizedLine(
                text: "这是第二行",
                frame: CGRect(x: 0.04, y: 0.05, width: 0.40, height: 0.04)
            )
        ]

        XCTAssertEqual(OCRTextLayout.text(from: lines), "这是第一行这是第二行")
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(OCRTextLayout.text(from: []))
        XCTAssertNil(OCRTextLayout.text(from: [
            RecognizedLine(text: "  \n ", frame: CGRect(x: 0, y: 0, width: 1, height: 0.1))
        ]))
    }

    func testQualityRequiresEnoughConfidenceAndText() {
        XCTAssertTrue(
            OCRQuality(text: "Hello", averageConfidence: 0.7, lineCount: 1).isReliable
        )
        XCTAssertFalse(
            OCRQuality(text: "x", averageConfidence: 0.7, lineCount: 1).isReliable
        )
        XCTAssertFalse(
            OCRQuality(text: "Hello", averageConfidence: 0.3, lineCount: 1).isReliable
        )
    }

    func testQualityScoreRewardsLongerResult() {
        let shortHighConfidence = OCRQuality(
            text: "Hi",
            averageConfidence: 0.9,
            lineCount: 1
        )
        let longerSlightlyLowerConfidence = OCRQuality(
            text: String(repeating: "context ", count: 10),
            averageConfidence: 0.7,
            lineCount: 2
        )
        XCTAssertGreaterThan(longerSlightlyLowerConfidence.score, shortHighConfidence.score)
    }

    func testEnhancerUpscalesSmallImage() throws {
        let image = try XCTUnwrap(makeImage(width: 200, height: 100))
        let enhanced = try XCTUnwrap(OCRImageEnhancer.enhanced(from: image))
        XCTAssertEqual(enhanced.width, 400)
        XCTAssertEqual(enhanced.height, 200)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
