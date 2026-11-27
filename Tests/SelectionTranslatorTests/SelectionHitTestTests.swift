import XCTest
@testable import SelectionTranslator

final class SelectionHitTestTests: XCTestCase {
    func testPointInsideFramePasses() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 80)
        XCTAssertTrue(SelectionHitTest.isPoint(CGPoint(x: 200, y: 140), near: frame))
    }

    func testPointNearFrameUsesTolerance() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 80)
        XCTAssertTrue(
            SelectionHitTest.isPoint(CGPoint(x: 90, y: 140), near: frame)
        )
        XCTAssertFalse(
            SelectionHitTest.isPoint(CGPoint(x: 70, y: 140), near: frame)
        )
    }

    func testCocoaPointIsFlippedToAXCoordinates() {
        let point = SelectionHitTest.accessibilityPoint(
            fromCocoa: CGPoint(x: 400, y: 200),
            primaryScreenHeight: 1_000
        )
        XCTAssertEqual(point, CGPoint(x: 400, y: 800))
    }

    func testDistantPointIsRejected() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 80)
        XCTAssertFalse(
            SelectionHitTest.isPoint(CGPoint(x: 600, y: 500), near: frame)
        )
    }
}
