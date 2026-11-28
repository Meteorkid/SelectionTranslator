import XCTest
@testable import SelectionTranslator

final class ApplicationTerminationTests: XCTestCase {
    func testStartupGraceCancelsQuit() {
        let started = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            ApplicationTerminationPolicy.shouldTerminate(
                processStartedAt: started,
                now: started.addingTimeInterval(2.9),
                isTestHost: false
            )
        )
    }

    func testQuitIsAllowedAfterGrace() {
        let started = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(
            ApplicationTerminationPolicy.shouldTerminate(
                processStartedAt: started,
                now: started.addingTimeInterval(3.0),
                isTestHost: false
            )
        )
    }

    func testTestHostAlwaysCancelsQuit() {
        let started = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            ApplicationTerminationPolicy.shouldTerminate(
                processStartedAt: started,
                now: started.addingTimeInterval(10),
                isTestHost: true
            )
        )
    }
}
