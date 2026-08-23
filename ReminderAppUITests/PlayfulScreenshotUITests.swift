import XCTest

/// v2.5.0 治愈游戏化 UI 改版截图目检：
/// 空态（挥手小狐狸）→ 创建提醒 → 今日时间线（发光球+规则徽章+宝箱）→
/// 打卡（彩带+庆祝卡）→ 日历（热力密度+吉祥物+本周跑道）→ 统计（城堡+花园）→ 周期选择器。
/// 产物通过 `xcrun xcresulttool export attachments` 导出后目检（UI 改动必须截图验证）。
final class PlayfulScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapturePlayfulScreens() throws {
        let app = XCUIApplication()
        // -appLanguage: UserDefaults 启动参数覆盖，强制中文文案（模拟器系统语言是英文）
        app.launchArguments += ["-tab", "0", "-appLanguage", "zh-Hans"]

        // 全新安装会弹通知权限系统弹窗（SpringBoard 层），拦下来点允许
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

        app.launch()
        app.swipeUp()      // 触发一次交互让 interruption monitor 生效
        app.swipeDown()

        snap(app, "01-home-empty")

        // 创建两条今日提醒（默认触发时间=下一分钟，必进今日时间线）
        try createReminder(app, title: "vitamin", cycle: "每天")
        try createReminder(app, title: "meditate", cycle: "每周")

        snap(app, "02-home-data")

        // 时间线发光球打卡 → 全屏彩带 + 庆祝卡
        let orb = app.buttons["打卡"].firstMatch
        if orb.waitForExistence(timeout: 5) {
            orb.tap()
            snap(app, "03-checkin-burst")
        }

        // 日历 Tab：热力密度 + 今日吉祥物 + 本周跑道
        app.tabBars.buttons.element(boundBy: 1).tap()
        snap(app, "04-calendar")

        // 统计 Tab：打卡城堡 + 本周花园
        app.tabBars.buttons.element(boundBy: 2).tap()
        snap(app, "05-stats")

        // 创建页周期选择器（emoji 卡片 + 彩虹光晕）
        app.tabBars.buttons.element(boundBy: 0).tap()
        openCreate(app)
        app.swipeUp()
        snap(app, "06-create-cycle")
        app.swipeDown()
        let cancel = app.buttons["取消"].firstMatch
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
    }

    // MARK: - 操作辅助

    private func openCreate(_ app: XCUIApplication) {
        let create = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "创建提醒")
        ).firstMatch
        if create.waitForExistence(timeout: 3) {
            create.tap()
            return
        }
        // 已有数据：右上菜单 → 新建提醒
        let menu = app.buttons["more-menu"].firstMatch
        if menu.waitForExistence(timeout: 3) {
            menu.tap()
            let item = app.buttons.containing(
                NSPredicate(format: "label CONTAINS %@", "新建提醒")
            ).firstMatch
            if item.waitForExistence(timeout: 3) {
                item.tap()
            }
        }
    }

    private func createReminder(_ app: XCUIApplication, title: String, cycle: String) throws {
        openCreate(app)

        // 表单第一个输入框是「自然语言快速创建」，必须按占位符精确命中「提醒标题」
        let titleField = app.textFields["提醒标题"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 8), "标题输入框未出现")
        titleField.tap()
        titleField.typeText(title)
        app.swipeUp()

        let option = app.buttons[cycle].firstMatch
        if option.waitForExistence(timeout: 4) {
            option.tap()
        }

        let save = app.buttons["保存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "保存按钮未出现")
        save.tap()

        // 回到首页（空态按钮消失或新标题上屏）；失败时留现场截图+元素快照
        let back = app.staticTexts[title].waitForExistence(timeout: 8)
        if !back {
            snap(app, "FAIL-after-save-\(title)")
            let alert = app.alerts.firstMatch
            let alertDesc = alert.exists ? "弹窗[\(alert.label)] " : ""
            let texts = app.staticTexts.allElementsBoundByIndex.prefix(25).map(\.label).joined(separator: "|")
            XCTFail("保存后未回首页：\(alertDesc)可见文本=\(texts)")
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
