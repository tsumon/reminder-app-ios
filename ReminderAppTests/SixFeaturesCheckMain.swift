import Foundation

/// 六项增强纯逻辑回归（macOS 命令行，无需模拟器）。
@main
struct SixFeaturesCheck {
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
        // ── 模型 URL / 解析 ──
        check("modelsURL 不重复 /v1",
              AIModelsAPI.modelsURL(from: "https://api.openai.com/v1")?.absoluteString == "https://api.openai.com/v1/models")
        check("modelsURL 去尾斜杠",
              AIModelsAPI.modelsURL(from: "http://localhost:11434/v1/")?.absoluteString == "http://localhost:11434/v1/models")
        check("modelsURL 空为 nil", AIModelsAPI.modelsURL(from: "  ") == nil)

        let json = """
        {"object":"list","data":[
          {"id":"gpt-4o","object":"model"},
          {"id":" gpt-4o-mini "},
          {"id":"gpt-4o"},
          {"id":""},
          {"object":"model"}
        ]}
        """.data(using: .utf8)!
        let ids = (try? AIModelsAPI.parseModelIDs(from: json)) ?? []
        check("parse 去重保序", ids == ["gpt-4o", "gpt-4o-mini"], "got \(ids)")

        // ── 原始 HTTP 错误 ──
        let raw401 = AIModelsAPI.formatHTTPError(
            status: 401,
            body: "{\"error\":{\"message\":\"Incorrect API key provided: sk-xxx\",\"type\":\"invalid_request_error\"}}\n"
        )
        check("401 含 HTTP 状态", raw401.hasPrefix("HTTP 401:"))
        check("401 含 body 摘要", raw401.contains("Incorrect API key"))
        check("401 不含套话", !raw401.contains("API Key 无效"))

        let raw404 = AIModelsAPI.formatHTTPError(status: 404, body: "{\"error\":\"not found\"}")
        check("404 原始", raw404 == "HTTP 404: {\"error\":\"not found\"}")

        // ── 上次选中 ──
        UserDefaults.standard.removeObject(forKey: AIModelsAPI.LastSelected.primaryKey)
        UserDefaults.standard.removeObject(forKey: AIModelsAPI.LastSelected.fallbackKey)
        AIModelsAPI.LastSelected.save("llama3.2", isFallback: false)
        AIModelsAPI.LastSelected.save("deepseek-chat", isFallback: true)
        check("记住主模型", AIModelsAPI.LastSelected.load(isFallback: false) == "llama3.2")
        check("记住备用模型", AIModelsAPI.LastSelected.load(isFallback: true) == "deepseek-chat")
        let ordered = AIModelsAPI.LastSelected.ordered(["a", "llama3.2", "b"], isFallback: false)
        check("上次选中排最前", ordered == ["llama3.2", "a", "b"], "got \(ordered)")

        // ── 模板 ──
        let idsTpl = ReminderTemplate.all.map(\.id)
        check("含报税", idsTpl.contains("tax"))
        check("含域名", idsTpl.contains("domain"))
        check("含生日", idsTpl.contains("birthday"))
        let tax = ReminderTemplate.all.first { $0.id == "tax" }!
        check("报税避开节假日", tax.holidayAware && tax.kind == .cycle && tax.cycle == .monthly)
        let domain = ReminderTemplate.all.first { $0.id == "domain" }!
        check("域名提前 30 天", domain.kind == .date && domain.advanceDays == 30)
        let bday = ReminderTemplate.all.first { $0.id == "birthday" }!
        check("生日默认公历", bday.dateType == .solarBirthday)

        // ── 分享文案 ──
        let text = ReminderShare.plainText(
            title: "域名续期",
            cycleLabel: "每年",
            nextTrigger: Date(timeIntervalSince1970: 1_800_000_000),
            note: "提前 30 天"
        )
        check("分享含标题", text.contains("提醒：域名续期"))
        check("分享含周期", text.contains("周期：每年"))
        check("分享含下次", text.contains("下次触发："))
        check("分享含备注", text.contains("备注：提前 30 天"))

        // ── 通知动作 ID ──
        check("confirm action id", NotificationActionIDs.confirm == "CONFIRM_ACTION")
        check("snooze action id", NotificationActionIDs.snooze == "SNOOZE_ACTION")
        check("category id", NotificationActionIDs.category == "REMINDER_CATEGORY")

        UserDefaults.standard.removeObject(forKey: AIModelsAPI.LastSelected.primaryKey)
        UserDefaults.standard.removeObject(forKey: AIModelsAPI.LastSelected.fallbackKey)

        print(failCount == 0 ? "== ALL SIX FEATURES CHECK PASS (\(passCount)) ==" : "== \(failCount) FAILURES / \(passCount) PASS ==")
        exit(failCount == 0 ? 0 : 1)
    }
}
