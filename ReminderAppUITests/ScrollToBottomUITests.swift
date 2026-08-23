import XCTest

/// v2.5.1: 打开 AI 对话框应自动滚到最新对话（用户反馈停在最早消息）
final class ScrollToBottomUITests: XCTestCase {
    func testOpenScrollsToBottom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_ai_fixture", "1", "-uitest_skip_permission", "1"]
        app.launch()

        let ai = app.buttons["ai-entry"]
        XCTAssertTrue(ai.waitForExistence(timeout: 8), "AI 入口未找到")
        ai.tap()

        // 等滚动动画完成
        sleep(3)

        let last = app.staticTexts["测试消息 15"].waitForExistence(timeout: 5)
        let firstVisible = app.staticTexts["测试消息 1"].isHittable // 虚拟化外元素 exists 会误报，用 isHittable
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ai-open-scrolled"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(last, "打开后未滚到底部（最后一条不在可视区）")
        XCTAssertFalse(firstVisible, "打开后顶部消息仍可见（未滚底）")
    }
}
