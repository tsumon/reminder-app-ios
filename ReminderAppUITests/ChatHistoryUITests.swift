import XCTest

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
    }

    private func openAIPage(_ app: XCUIApplication) {
        // 首页工具栏 AI 入口（v2.4.6 移到 trailing，带显式 accessibilityLabel）
        let sparkles = app.buttons["ai-entry"]
        XCTAssertTrue(sparkles.waitForExistence(timeout: 8), "AI 入口未找到")
        sparkles.tap()
    }

    func testHistorySurvivesAppRestart() throws {
        let app = XCUIApplication()
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
