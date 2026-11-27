import XCTest
@testable import SelectionTranslator

final class TextRangeResolverTests: XCTestCase {
    func testFindsSelectedTextInsideFullText() {
        let fullText = "The quick brown fox jumps over the lazy dog."
        let selected = "brown fox"
        let range = TextRangeResolver.firstRange(of: selected, in: fullText)
        XCTAssertEqual(range?.location, 10)
        XCTAssertEqual(range?.length, 9)
    }

    func testMissingSelectionReturnsNil() {
        XCTAssertNil(
            TextRangeResolver.firstRange(of: "not present", in: "The quick brown fox")
        )
    }

    func testEmptyInputsReturnNil() {
        XCTAssertNil(TextRangeResolver.firstRange(of: "", in: "text"))
        XCTAssertNil(TextRangeResolver.firstRange(of: "text", in: ""))
    }
}
