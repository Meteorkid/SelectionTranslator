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

    func testOrdinaryLineGapUsesSingleNewline() {
        let lines = [
            RecognizedLine(
                text: "line one",
                frame: CGRect(x: 0.10, y: 0.00, width: 0.70, height: 0.04)
            ),
            RecognizedLine(
                text: "line two",
                frame: CGRect(x: 0.10, y: 0.06, width: 0.70, height: 0.04)
            )
        ]

        XCTAssertEqual(OCRTextLayout.text(from: lines), "line one\nline two")
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(OCRTextLayout.text(from: []))
        XCTAssertNil(OCRTextLayout.text(from: [
            RecognizedLine(text: "  \n ", frame: CGRect(x: 0, y: 0, width: 1, height: 0.1))
        ]))
    }
}
