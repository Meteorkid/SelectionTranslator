import XCTest
@testable import SelectionTranslator

final class ScreenshotOverlayDetectorTests: XCTestCase {
    func testFullDisplayOverlayIsRecognized() {
        let display = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        XCTAssertTrue(
            ScreenshotOverlayDetector.coversWholeDisplay(display, [display])
        )
    }

    func testPartialOverlayIsIgnored() {
        let display = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let half = CGRect(x: 0, y: 0, width: 756, height: 982)
        XCTAssertFalse(
            ScreenshotOverlayDetector.coversWholeDisplay(half, [display])
        )
    }

    func testOverlayCanCoverASecondaryDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let secondary = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        XCTAssertTrue(
            ScreenshotOverlayDetector.coversWholeDisplay(secondary, [primary, secondary])
        )
    }
}
