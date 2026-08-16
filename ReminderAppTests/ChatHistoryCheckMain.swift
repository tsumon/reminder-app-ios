import Foundation

/// AI 对话历史持久化回归检查（v2.4.6）
///
/// 以 macOS 命令行工具形式运行（无需 iOS 模拟器 / host app），
/// 直接把产品代码 ReminderApp/Services/ChatHistoryStore.swift 编译进来。
/// 背景：用户反馈 v2.4.3 后 iOS 历史仍失效——用可复现的往返断言锁定存储层行为。
/// 覆盖：save→load 往返（内容/角色/时间保真）、空内容步骤气泡过滤、
/// 200 条截断（保留最新）、损坏数据容错、清空。
@main
struct ChatHistoryCheck {

    static var passCount = 0
    static var failCount = 0

    static func check(_ name: String, _ cond: Bool, _ detail: String = "") {
        if cond {
            print("PASS \(name)")
            passCount += 1
        } else {
            print("FAIL \(name) \(detail)")
            failCount += 1
        }
    }

    static func main() {
        // ChatHistoryStore 硬编码 UserDefaults.standard——测试前后清理，
        // 幂等且不在真实 defaults 里残留测试数据。
        ChatHistoryStore.clear()

        // ── 1. save → load 往返 ──
        let msgs: [ChatMessage] = [
            ChatMessage(role: .user, content: "每个星期天提醒我打针", timestamp: Date(timeIntervalSince1970: 1755300000)),
            ChatMessage(role: .assistant, content: "已创建每周日 09:00 的提醒", timestamp: Date(timeIntervalSince1970: 1755300001)),
            ChatMessage(role: .user, content: "谢谢", timestamp: Date(timeIntervalSince1970: 1755300002)),
        ]
        ChatHistoryStore.save(msgs)
        let loaded = ChatHistoryStore.load()
        check("往返条数", loaded.count == 3, "got \(loaded.count)")
        check("往返内容保真", loaded.map(\.content) == ["每个星期天提醒我打针", "已创建每周日 09:00 的提醒", "谢谢"])
        check("往返角色保真", loaded.map(\.role) == [.user, .assistant, .user])
        check("往返时间保真", loaded.map(\.timestamp.timeIntervalSince1970) == [1755300000, 1755300001, 1755300002])

        // ── 2. 空 content 消息（工具步骤气泡）不落盘 ──
        let withSteps = msgs + [ChatMessage(role: .assistant, content: "", timestamp: Date(), toolSteps: [
            ToolStep(name: "create_reminder", status: "done", summary: nil)
        ])]
        ChatHistoryStore.save(withSteps)
        check("空内容步骤气泡过滤", ChatHistoryStore.load().count == 3)

        // ── 3. 200 条截断 ──
        let many = (0..<260).map { ChatMessage(role: .user, content: "msg\($0)", timestamp: Date()) }
        ChatHistoryStore.save(many)
        let truncated = ChatHistoryStore.load()
        check("200 条截断", truncated.count == 200, "got \(truncated.count)")
        check("截断保留最新", truncated.first?.content == "msg60", "got \(truncated.first?.content ?? "nil")")

        // ── 4. 损坏数据容错：不崩、返回空 ──
        UserDefaults.standard.set(Data("not a json {{{".utf8), forKey: "ai_chat_history")
        check("损坏数据返回空", ChatHistoryStore.load().isEmpty)

        // ── 5. clear ──
        ChatHistoryStore.save(msgs)
        ChatHistoryStore.clear()
        check("清空后为空", ChatHistoryStore.load().isEmpty)

        ChatHistoryStore.clear() // 清理测试痕迹

        print(failCount == 0 ? "== ALL CHAT HISTORY REGRESSION PASS ==" : "== \(failCount) FAILURES ==")
        exit(failCount == 0 ? 0 : 1)
    }
}
