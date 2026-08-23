import XCTest
import Foundation

/// v2.4.6: AI 对话历史持久化 UI 回归（真实模拟器全链路）
///
/// 流程：进入 AI 页（首页左上角 sparkles）→ 断言注入历史恢复（load）→
/// 发送消息（预置假本地端点 → 网络失败走 catch）→ 杀 App 重进 →
/// 断言用户消息仍在（save→load 全链路往返）。
/// 预置条件（测试前注入 plist）：ai_isLocal=true + ai_endpoint=http://127.0.0.1:9/v1，
/// ai_chat_history 已含 3 条历史。
final class ChatHistoryUITests: XCTestCase {

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

    private func openAIPage(_ app: XCUIApplication) {
        // 首页左上角 AI 入口（v2.4.9 移回 leading，带显式 accessibilityIdentifier）
        let sparkles = app.buttons["ai-entry"]
        XCTAssertTrue(sparkles.waitForExistence(timeout: 8), "AI 入口未找到")
        sparkles.tap()
    }

    func testHistorySurvivesAppRestart() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_ai_fixture", "1", "-uitest_skip_permission", "1"]
        app.launch()

        openAIPage(app)

        // 断言 1：注入的 3 条历史已恢复（load 路径）
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "打针")).firstMatch
            .waitForExistence(timeout: 8), "注入的历史未显示（load 失效）")

        // 发送一条新消息（假端点 → 网络失败 → catch 路径，用户消息仍应上屏+保存）
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5), "输入框未找到")
        input.tap()
        input.typeText("uitest-save")

        let send = app.buttons["send-button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "发送按钮未找到")
        send.tap()

        // 断言 2：用户消息上屏（失败信息带上实际文本列表便于定位）
        let appeared = app.staticTexts["uitest-save"].waitForExistence(timeout: 8)
        let ctx = app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(15).joined(separator: " | ")
        XCTAssertTrue(appeared, "发送的用户消息未上屏；实际文本: \(ctx)")

        // 杀 App 冷启重进
        app.terminate()
        app.launch()

        openAIPage(app)

        // 断言 3：重启后历史完整（save→load 全链路）
        XCTAssertTrue(app.staticTexts["uitest-save"].waitForExistence(timeout: 8),
                      "重启后用户消息丢失——save 或 load 失效")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "打针")).firstMatch
            .waitForExistence(timeout: 5), "重启后注入历史丢失")
    }
}


/// v2.4.6 用户反馈复现：多轮对话后，退出聊天窗口再进只剩"当前对话"两条。
/// 该测试逐轮断言累积，抓历史被覆盖的时刻。
final class MultiTurnHistoryUITests: XCTestCase {

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

    private func openAIPage(_ app: XCUIApplication) {
        let sparkles = app.buttons["ai-entry"]
        XCTAssertTrue(sparkles.waitForExistence(timeout: 8), "AI 入口未找到")
        sparkles.tap()
    }

    private func send(_ app: XCUIApplication, _ text: String) {
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5), "输入框未找到")
        input.tap()
        sleep(1)
        app.typeText(text)
        let send = app.buttons["send-button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "发送按钮未找到")
        send.tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 8), "(\(text)) 未上屏")
        sleep(1)
    }

    private func historyCount(_ app: XCUIApplication) -> Int {
        // 菜单标题 "查看历史（N 条）" / "View History (N)"
        let menu = app.images["clock.arrow.circlepath"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "历史菜单未找到")
        menu.tap()
        let item = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*\\d+.*")).firstMatch
        let ok = item.waitForExistence(timeout: 4)
        let label = ok ? item.label : "?"
        if ok { app.tap() } // 点空白收起
        let m = label.range(of: #"\d+"#, options: .regularExpression)
        return m.map { Int(label[$0])! } ?? -1
    }

    func testMultiTurnAccumulatesAcrossReentry() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_ai_fixture", "1", "-uitest_skip_permission", "1"]
        app.launch()
        openAIPage(app)

        // 第 1 轮
        send(app, "turn-one")
        let c1 = historyCount(app)
        // 第 2 轮（不退出页面连续对话）
        send(app, "turn-two")
        let c2 = historyCount(app)
        XCTAssertTrue(c2 > c1, "连续第二轮后条数未增加: \(c1) -> \(c2)")

        // 退出聊天窗口（pop 回首页）再进
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        sleep(1)
        openAIPage(app)
        // v2.5.0: 历史列表加载后自动滚到底部，早前消息在可视区外（XCUITest 只命中可视元素，
        // 且 swipeUp/swipeDown 依赖列表实现方向不稳）——改用条数断言：未被覆盖 = 条数不降
        let c3 = historyCount(app)
        XCTAssertTrue(c3 >= c2, "重进后历史条数下降（历史被覆盖/丢失——用户症状）: \(c2) -> \(c3)")
        XCTAssertTrue(app.staticTexts["turn-two"].waitForExistence(timeout: 4), "turn-two 丢失")

        // 杀 App 重进：条数仍不降（save→load 全链路）
        app.terminate()
        app.launch()
        openAIPage(app)
        let c4 = historyCount(app)
        XCTAssertTrue(c4 >= c2, "杀 App 重进后历史条数下降: \(c2) -> \(c4)")
    }
}

