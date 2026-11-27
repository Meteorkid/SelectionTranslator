import XCTest

final class SelectionTranslatorUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOnboardingShowsPermissionGuide() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_FORCE_ONBOARDING"] = "1"
        app.launchEnvironment["ST_DISABLE_UPDATER"] = "1"
        app.launch()

        XCTAssertTrue(app.windows["欢迎使用划词翻译"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["建议先完成两项系统授权"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["辅助功能"].exists)
        XCTAssertTrue(app.staticTexts["屏幕录制"].exists)
        XCTAssertTrue(app.buttons["开始使用"].exists)
    }

    func testSettingsShowsReadingAndContextControls() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["ST_DISABLE_UPDATER"] = "1"
        app.launchEnvironment["ST_OPEN_SETTINGS"] = "1"
        app.launchEnvironment["ST_SETTINGS_TAB"] = "translation"
        app.launch()

        XCTAssertTrue(app.windows["设置"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["译文风格"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["术语表"].exists)
        XCTAssertTrue(app.staticTexts["阅读节奏"].exists)

        let dataTab = app.buttons["settings-tab-data"]
        XCTAssertTrue(dataTab.exists)
        dataTab.click()
        XCTAssertTrue(app.staticTexts["按 App 排除"].waitForExistence(timeout: 5))

        app.buttons["settings-tab-context"].click()
        XCTAssertTrue(app.buttons["从 PDF 导入"].waitForExistence(timeout: 5))
    }
}
