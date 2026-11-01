import XCTest

/// Actual native flows on a dedicated simulator; sample reminders are created through the form.
final class RefreshUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    @MainActor private func app() -> XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["-uitest_isolate_notifications","-uitest_skip_permission","1","-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]
        return app
    }
    @MainActor private func select(_ title:String,in app:XCUIApplication) {
        let dock=app.otherElements["soft-tab-dock"]
        XCTAssertTrue(dock.waitForExistence(timeout:10))
        dock.buttons[title].tap()
        let committed=expectation(description:"Tab transition")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { committed.fulfill() }
        wait(for:[committed],timeout:2)
    }
    @MainActor private func snap(_ name:String) {
        let item=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        item.name=name;item.lifetime = .keepAlways;add(item)
    }
    @MainActor func testCaptureNativeRefreshAndCancelEditing() throws {
        executionTimeAllowance=120
        let app=app();app.launch()
        let input=app.textFields["quick-reminder-input"]
        XCTAssertTrue(input.waitForExistence(timeout:15))
        input.tap();input.typeText("明天9点给绿植浇水")
        app.buttons["检查规则"].tap()
        let title=app.textFields["提醒标题"]
        XCTAssertTrue(title.waitForExistence(timeout:8))
        XCTAssertEqual(title.value as? String,"给绿植浇水")
        snap("create-2.9")
        app.buttons["保存"].firstMatch.tap()
        XCTAssertTrue(input.waitForExistence(timeout:8))
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"hittable == true"),object:input)
        wait(for:[ready],timeout:5)
        snap("home-2.9")
        let countBefore=app.staticTexts.matching(identifier:"给绿植浇水").count
        app.buttons["新建提醒"].firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout:8))
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(input.waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts.matching(identifier:"给绿植浇水").count,countBefore)
        select("日历",in:app)
        snap("calendar-2.9")
        let addDay=app.buttons["添加当天提醒"]
        for _ in 0..<3 where !addDay.isHittable { app.swipeUp() }
        XCTAssertTrue(addDay.exists)
        addDay.tap()
        XCTAssertTrue(title.waitForExistence(timeout:8))
        app.buttons["取消"].firstMatch.tap()
        select("统计",in:app)
        XCTAssertTrue(app.staticTexts["每次确认，都有记录"].waitForExistence(timeout:8))
        snap("stats-2.9")
        select("设置",in:app)
        snap("settings-2.9")
    }
    @MainActor func testHealthCardOpensActionableDiagnostics() throws {
        executionTimeAllowance=120
        let app=app();app.launch()
        let health=app.buttons["notification-health"]
        for _ in 0..<3 where !health.isHittable { app.swipeUp() }
        XCTAssertTrue(health.waitForExistence(timeout:8))
        health.tap()
        XCTAssertTrue(app.buttons["申请通知权限"].waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["发送10秒测试提醒"].exists)
    }
}
