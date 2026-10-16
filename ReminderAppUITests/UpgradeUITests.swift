import XCTest

final class UpgradeUITests: XCTestCase {
    @MainActor func testAutomaticSyncConflictOffersChoiceAndCancelPreservesRevisions() async throws {
        let server = URL(string: "http://127.0.0.1:8899")!
        _ = try await URLSession.shared.data(from: server.appendingPathComponent("dav-reset"))
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_skip_permission", "1", "-uitest_auto_sync_conflict",
            "-sync_url", "http://127.0.0.1:8899/dav/", "-sync_user", "uitest", "-sync_auto", "YES",
            "-sync_last_sync", "0", "-sync_remote_stamp_v3", "uitest-unseen",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        defer {
            app.terminate()
            app.launchArguments = ["-uitest_skip_permission", "1", "-uitest_clear_sync_fixture"]
            app.launch(); app.terminate()
        }
        app.launch()
        let chooseLocal = app.buttons["使用本地并上传"]
        XCTAssertTrue(chooseLocal.waitForExistence(timeout: 15), "Automatic sync must show the shared conflict controls")
        XCTAssertTrue(app.buttons["使用远程并保留本机独有提醒"].exists)
        let (beforeData, _) = try await URLSession.shared.data(from: server.appendingPathComponent("dav-state"))
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: beforeData) as? [String: Any])
        XCTAssertGreaterThan(before["reads"] as? Int ?? 0, 0)
        XCTAssertEqual(before["writes"] as? Int, 0)
        app.buttons["取消"].tap()
        XCTAssertFalse(chooseLocal.exists)
        let localRow = app.staticTexts["Automatic sync local revision"]
        for _ in 0..<6 where !localRow.exists { app.swipeUp() }
        XCTAssertTrue(localRow.exists)
        let (afterData, _) = try await URLSession.shared.data(from: server.appendingPathComponent("dav-state"))
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: afterData) as? [String: Any])
        XCTAssertEqual(after["writes"] as? Int, 0)
        let originalBackup = try JSONSerialization.data(withJSONObject: XCTUnwrap(before["backup"]), options: [.sortedKeys])
        let remainingBackup = try JSONSerialization.data(withJSONObject: XCTUnwrap(after["backup"]), options: [.sortedKeys])
        XCTAssertEqual(originalBackup, remainingBackup, "Cancel must leave the remote revision untouched")
    }

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
