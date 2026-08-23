import XCTest
import Foundation

/// ask_user 历法澄清全链路 UI 回归（本地 mock 端点按剧本应答，配套
/// ReminderAppUITests/MockAIServer.py：先 `python3 MockAIServer.py` 再跑本测试；
/// 请求侧断言（prompt 规则/工具定义/历史携带）在测试后 curl /state 分析）。
///
/// 验证链路：纯数字日期输入 → 模型返回 ask_user → 客户端拦截 Agent 循环、
/// 渲染选项按钮 → 点「农历」→ 选项作为 user 消息带历史重新进入 chatLoop →
/// create_reminder 执行 → 流式回复上屏 → 按钮消失；第二段「211」沿用创建。
///
/// 注意：XCUITest 的 app 容器是会话级临时的（test 结束即被 xcodebuild 删除），
/// 别试图事后从文件系统验证落库——mock 录制里的 tool result（"已创建提醒"）
/// 才是落库证据（handleCreate 返回该文本前已 insert+save，失败会打
/// "[AIChat] create save# failed" 统一日志）。
final class AskUserCalendarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // v2.5.0: 全新安装首启会弹通知权限系统弹窗，拦下来点允许（否则抢焦点、typeText 落空）
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

    func testAmbiguousDateAskUserButtonFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ai_endpoint", "http://127.0.0.1:8899/v1",
            "-ai_is_local", "1",
            "-ai_model", "mock-test",
            "-uitest_skip_permission", "1",
            "-uitest_reset_mock", "1"
        ]
        app.launch()

        // 首页左上角 AI 入口
        let entry = app.buttons["ai-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8), "AI 入口未找到")
        entry.tap()

        // 隔离：清空历史（ChatHistoryStore 跨 launch 持久化，旧消息会让
        // 文本断言假阳性 / 时序错位——第三、四次运行连续 flaky 的根因）
        let historyMenu = app.buttons["history-menu"]
        if historyMenu.exists {
            historyMenu.tap()
            let clear = app.buttons["clear-history"]
            if clear.waitForExistence(timeout: 3) {
                clear.tap()
            }
        }

        // —— 第 1 段：「baba 2.10」→ mock 返回 ask_user → 应渲染问题 + 两个按钮 ——
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5), "输入框未找到")
        input.tap()
        sleep(1)
        input.tap()   // 菜单刚收起时首击可能没聚焦，补一击
        app.typeText("baba 2.10")
        app.buttons["send-button"].tap()

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "新历还是农历")).firstMatch
            .waitForExistence(timeout: 15), "ask_user 问题未上屏")
        let solar = app.buttons["新历"]
        let lunar = app.buttons["农历"]
        XCTAssertTrue(solar.waitForExistence(timeout: 5), "「新历」按钮未渲染")
        XCTAssertTrue(lunar.exists, "「农历」按钮未渲染")

        // —— 点「农历」→ 带历史重入 → create_reminder → 流式回复上屏 ——
        lunar.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "已按农历创建：baba")).firstMatch
            .waitForExistence(timeout: 20), "点选后未创建或回复未上屏")
        XCTAssertFalse(lunar.exists, "选项按钮点击后未移除（防重复点失效）")

        // —— 第 2 段：「mama 211」→ mock 剧本：沿用历法直接创建 ——
        let input2 = app.textFields.firstMatch
        XCTAssertTrue(input2.waitForExistence(timeout: 5), "第二段输入框未找到")
        input2.tap()
        sleep(1)
        input2.tap()
        app.typeText("mama 211")
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "已按农历创建：mama")).firstMatch
            .waitForExistence(timeout: 20), "第二段未创建或回复未上屏")
    }
}

extension XCTestCase {

}
