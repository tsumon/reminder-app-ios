import XCTest

final class SixFeaturesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "notification-permission") { alert in
            for label in ["Allow", "允许", "好", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    private func shot(_ name: String) {
        let dir = URL(fileURLWithPath: "/Users/mac/Desktop/循环提醒-six")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: dir.appendingPathComponent(name))
        let out = URL(fileURLWithPath: "/Users/mac/reminder-soft-ui/out/six")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? data.write(to: out.appendingPathComponent(name))
    }

    private func openAISettings(_ app: XCUIApplication) {
        let sparkles = app.buttons["ai-entry"]
        XCTAssertTrue(sparkles.waitForExistence(timeout: 8), "AI 入口未找到")
        sparkles.tap()
        let gear = app.buttons["ai-settings-entry"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8), "AI 设置入口未找到")
        gear.tap()
    }

    func testPingAndModelSearch() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest_skip_permission", "1",
            "-ai_endpoint", "http://127.0.0.1:8898/v1",
            "-ai_is_local", "1",
        ]
        app.launch()
        openAISettings(app)

        let ping = app.buttons["ping-models-primary"]
        XCTAssertTrue(ping.waitForExistence(timeout: 8), "测连通按钮未出现")
        ping.tap()
        XCTAssertTrue(app.alerts.element.waitForExistence(timeout: 10), "测连通应弹出结果")
        shot("ios-ping.png")
        let alertText = app.alerts.element.staticTexts.allElementsBoundByIndex.map(\.label).joined()
        XCTAssertTrue(alertText.contains("连通成功") || alertText.contains("HTTP") || alertText.contains("模型"),
                      "测连通文案不含数量或原始错误: \(alertText)")
        app.alerts.buttons.firstMatch.tap()

        let fetch = app.buttons["fetch-models-primary"]
        XCTAssertTrue(fetch.waitForExistence(timeout: 5))
        fetch.tap()
        let search = app.textFields["model-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "模型搜索框未出现")
        search.tap()
        search.typeText("llama")
        XCTAssertTrue(app.buttons["model-choice-llama3.2"].waitForExistence(timeout: 4), "搜索未留下 llama3.2")
        shot("ios-model-search.png")
        app.buttons["model-choice-llama3.2"].tap()
        let modelField = app.textFields["ai-model"]
        XCTAssertTrue(modelField.waitForExistence(timeout: 3))
        XCTAssertEqual(modelField.value as? String, "llama3.2")
    }

    func testReminderTemplatesFillForm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_skip_permission", "1"]
        app.launch()

        let plus = app.buttons["新建提醒"].firstMatch
        if plus.waitForExistence(timeout: 4) {
            plus.tap()
        } else {
            let create = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "创建提醒")).firstMatch
            if create.waitForExistence(timeout: 3) {
                create.tap()
            } else {
                let menu = app.buttons["more-menu"].firstMatch
                XCTAssertTrue(menu.waitForExistence(timeout: 5), "找不到新建入口")
                menu.tap()
                app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "新建提醒")).firstMatch.tap()
            }
        }

        let tax = app.buttons["reminder-template-tax"]
        XCTAssertTrue(tax.waitForExistence(timeout: 8), "报税模板未出现")
        tax.tap()
        let titleField = app.textFields["提醒标题"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 4))
        XCTAssertEqual(titleField.value as? String, "报税")
        shot("ios-template-tax.png")

        app.buttons["reminder-template-birthday"].tap()
        XCTAssertEqual(titleField.value as? String, "生日")
        shot("ios-template-birthday.png")
    }
}
