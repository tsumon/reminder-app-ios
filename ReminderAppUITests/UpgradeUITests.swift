import XCTest

final class UpgradeUITests: XCTestCase {
    @MainActor func testHomeQuickEntryOpensEditableParserForm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_skip_permission", "1", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let input = app.textFields["quick-reminder-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("明天9点换滤芯")
        app.buttons["检查规则"].tap()
        XCTAssertTrue(app.textFields["提醒标题"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["提醒标题"].value as? String, "换滤芯")
        XCTAssertTrue(app.buttons["保存"].isEnabled)
        app.buttons["取消"].tap()
    }

    @MainActor func testComplexQuickEntryRequiresRuleReview() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_skip_permission", "1", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let input = app.textFields["quick-reminder-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("每季度第二周周三缴费")
        app.buttons["检查规则"].tap()
        XCTAssertTrue(app.switches["confirm-complex-rule"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        app.buttons["取消"].tap()
    }
}
