import Foundation
import XCTest
@testable import SelectionTranslator

final class OnboardingStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SelectionTranslatorTests.Onboarding.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstRunShowsOnboarding() {
        XCTAssertTrue(OnboardingState.shouldShow(defaults: defaults))
    }

    func testCompletedStateSuppressesOnboarding() {
        OnboardingState.markCompleted(defaults: defaults)
        XCTAssertFalse(OnboardingState.shouldShow(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: OnboardingState.completedKey))
    }

    func testResetAllowsOnboardingAgain() {
        OnboardingState.markCompleted(defaults: defaults)
        OnboardingState.reset(defaults: defaults)
        XCTAssertTrue(OnboardingState.shouldShow(defaults: defaults))
    }
}
