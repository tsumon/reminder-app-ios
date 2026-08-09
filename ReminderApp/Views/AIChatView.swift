import SwiftUI
import SwiftData

// MARK: - Chat 消息模型

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole: Equatable {
        case user, assistant, system, tool
    }
}

// MARK: - AI 对话页面

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AISettings.shared
    @StateObject private var voice = VoiceRecognizer.shared

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scrollToID: UUID?

    @Query(sort: \Reminder.title) private var reminders: [Reminder]

    var body: some View {
        VStack(spacing: 0) {
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            welcomeView
                        }

                        ForEach(messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }

                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(12)
                                Spacer()
                            }
                        }

                        if let err = errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: isLoading) { _ in
                    if let last = messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .glassPageBackground()

            // 底部输入栏
            inputBar
        }
        .navigationTitle("AI 助手".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AISettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .onAppear {
            if !settings.isConfigured {
                let guide = "👋 你好！请先在右上角设置中配置 API Key（支持 DeepSeek / 通义千问 / 豆包等，均有免费额度）。\n\n我能帮你：\n• 创建提醒「每天提醒我喝水」\n• 查看列表「有什么提醒」\n• 确认完成「确认喝水」\n• 推迟/删除提醒"
                messages.append(ChatMessage(
                    role: .assistant,
                    content: guide,
                    timestamp: Date()
                ))
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
                .padding(.top, 40)
            Text("跟我说你想提醒什么".localized)
                .font(.title3.weight(.semibold))
            Text("\"每天8点提醒我吃药\"\n\"每年提醒我妈生日\"\n\"每周一早上开会\"".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 40)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            if voice.isRecording {
                recordingOverlay
            }

            HStack(alignment: .bottom, spacing: 8) {
                // 语音按钮
                Button {
                    toggleVoice()
                } label: {
                    Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(voice.isRecording ? .red : .secondary)
                        .frame(width: 36, height: 36)
                }
                .disabled(isLoading)
                .animation(.easeInOut, value: voice.isRecording)

                // 文本输入
                TextField("输入或点击麦克风说话...".localized, text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .disabled(isLoading)

                // 发送按钮
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
                                ? .gray
                                : .purple
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    private var recordingOverlay: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.red)
            Text(voice.transcribedText.isEmpty ? "正在聆听..." : voice.transcribedText)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Actions

    private func toggleVoice() {
        if voice.isRecording {
            voice.stopRecording()
            if !voice.transcribedText.isEmpty {
                inputText = voice.transcribedText
                sendMessage()
            }
        } else {
            Task {
                let granted = await voice.requestAuthorization()
                if granted {
                    do { try voice.startRecording() }
                    catch { errorMessage = error.localizedDescription }
                } else {
                    errorMessage = "请在系统设置中允许语音识别权限"
                }
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        // ── API 模式 ──
        guard settings.isConfigured else {
            errorMessage = "请先在右上角设置中配置 API Key"
            return
        }

        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text, timestamp: Date()))
        isLoading = true

        Task {
            await chatLoop(userText: text)
        }
    }

    // MARK: - Chat Loop（多轮工具调用）

    private func chatLoop(userText: String) async {
        var conversation: [AIService.ChatMessage] = [
            .init(role: "system", content: AITools.systemPrompt),
            .init(role: "user", content: userText)
        ]

        var maxTurns = 5

        while maxTurns > 0 {
            maxTurns -= 1

            do {
                let reply = try await AIService.shared.chat(
                    model: settings.model,
                    messages: conversation,
                    endpoint: settings.apiEndpoint,
                    apiKey: settings.apiKey
                )

                // 有 tool_calls → 执行工具后继续
                if let toolCalls = reply.tool_calls, !toolCalls.isEmpty {
                    for tc in toolCalls {
                        let result = await executeTool(name: tc.function.name, args: tc.function.arguments)
                        conversation.append(.init(role: "assistant", tool_calls: [tc]))
                        conversation.append(.init(role: "tool", content: result, tool_call_id: tc.id))
                    }
                    continue
                }

                // 纯文本回复
                if let content = reply.content, !content.isEmpty {
                    await MainActor.run {
                        messages.append(ChatMessage(role: .assistant, content: content, timestamp: Date()))
                        isLoading = false
                    }
                    return
                }

                // 空回复
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: "好的，已处理。", timestamp: Date()))
                    isLoading = false
                }
                return

            } catch {
                await MainActor.run {
                    errorMessage = "\(error.localizedDescription)"
                    isLoading = false
                }
                return
            }
        }

        await MainActor.run {
            messages.append(ChatMessage(role: .assistant, content: "对话轮次过多，请重新描述你的需求。", timestamp: Date()))
            isLoading = false
        }
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, args jsonStr: String) async -> String {
        guard let data = jsonStr.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "参数解析失败"
        }

        switch name {
        case "create_reminder":
            return await handleCreate(args: args)
        case "list_reminders":
            return await handleList()
        case "confirm_reminder":
            return await handleConfirm(args: args)
        case "snooze_reminder":
            return await handleSnooze(args: args)
        case "delete_reminder":
            return await handleDelete(args: args)
        default:
            return Localized("未知工具: %@", name)
        }
    }

    // MARK: - Tool Handlers

    private func handleCreate(args: [String: Any]) async -> String {
        let title = args["title"] as? String ?? "未命名提醒"
        let kind = args["kind"] as? String ?? "cycle"
        let note = args["note"] as? String ?? ""
        let cycle = args["cycle"] as? String ?? "weekly"
        let customDays = args["custom_days"] as? Int ?? 0
        let dateType = args["date_type"] as? String
        // 不能给月/日一个「看起来合法」的缺省值（如 1），
        // 否则模型漏传参数时会被静默当成 1月1日，绕过下面的合法性守卫。
        let targetMonthRaw = (args["target_month"] as? Int)
            ?? (args["target_month"] as? Double).map(Int.init)
            ?? (args["target_month"] as? String).flatMap(Int.init)
        let targetDayRaw = (args["target_day"] as? Int)
            ?? (args["target_day"] as? Double).map(Int.init)
            ?? (args["target_day"] as? String).flatMap(Int.init)
        let targetMonth = targetMonthRaw ?? 0
        let targetDay = targetDayRaw ?? 0
        let advanceDays = args["advance_days"] as? Int ?? 3
        let reminderHour = args["reminder_hour"] as? Int ?? 9
        let reminderMinute = args["reminder_minute"] as? Int ?? 0
        let holidayName = args["holiday_name"] as? String
        // v1.9.0 fix: 规则提醒（第N周周X）参数
        let rulePeriodRaw = args["rule_period"] as? String
        let ruleWeekRaw = (args["rule_week"] as? Int)
            ?? (args["rule_week"] as? Double).map(Int.init)
            ?? (args["rule_week"] as? String).flatMap(Int.init)
        let ruleWeekdayRaw = (args["rule_weekday"] as? Int)
            ?? (args["rule_weekday"] as? Double).map(Int.init)
            ?? (args["rule_weekday"] as? String).flatMap(Int.init)

        // 日期类提醒必须带合法月日，否则引擎算不出正确触发时间。
        // 与其创建一个会误触发的提醒，不如让用户补一句。
        if kind == "date" {
            if dateType == "holiday" {
                if (holidayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    return "需要指定节假日名称（例如：春节、中秋节）才能创建节假日提醒。"
                }
            } else if !(1...12).contains(targetMonth) || !(1...31).contains(targetDay) {
                return "需要具体的公历/农历月日才能创建日期提醒（例如：农历八月十五、公历5月1日）。请补充月日，我再为你创建。"
            }
        }
        // v1.9.0 fix: 规则提醒必须带全 频率/第几周/周几
        if kind == "rule" {
            guard let rp = rulePeriodRaw, let rw = ruleWeekRaw, let rwd = ruleWeekdayRaw else {
                return "规则提醒需要指定频率（每月/每季度/每年）、第几周和星期几，例如：每季度第一周周四。请补充完整，我再为你创建。"
            }
            guard ["monthly", "quarterly", "yearly"].contains(rp),
                  (1...5).contains(rw), (1...7).contains(rwd) else {
                return "规则提醒参数不合法：频率应为每月/每季度/每年，第几周 1-5，星期几 1=周一...7=周日。"
            }
        }

        let now = Date()
        // 首次锚点：下一个到达 reminderHour:reminderMinute 的时刻（cycle 用作周期锚点）
        var anchor = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now) ?? now
        if anchor <= now { anchor = Calendar.current.date(byAdding: .day, value: 1, to: anchor) ?? anchor }

        var holidayID: String? = nil
        if let hn = holidayName {
            holidayID = HolidayService.search(by: hn)?.id
        }

        let reminderKind: ReminderKind = kind == "date" ? .date : (kind == "rule" ? .rule : .cycle)
        let cycleEnum: ReminderCycle = {
            switch cycle {
            case "once":      return .once
            case "daily":     return .daily
            case "weekly":    return .weekly
            case "biweekly":  return .biweekly
            case "monthly":   return .monthly
            case "quarterly": return .quarterly
            case "yearly":    return .yearly
            default:          return .custom
            }
        }()

        let dateTypeEnum: DateReminderType? = {
            switch dateType {
            case "solar_birthday": return .solarBirthday
            case "lunar_birthday": return .lunarBirthday
            case "holiday":        return .holiday
            default:               return nil
            }
        }()

        let reminder = Reminder(
            title: title,
            note: note,
            kind: reminderKind,
            cycle: cycleEnum,
            customDays: customDays,
            dateType: dateTypeEnum,
            targetMonth: targetMonth,
            targetDay: targetDay,
            advanceDays: advanceDays,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            holidayID: holidayID,
            // v1.9.0 fix: 规则提醒参数（AI 传英文，映射到中文 rawValue 枚举）
            rulePeriod: rulePeriodRaw.map { rp -> RulePeriod in
                switch rp {
                case "monthly": return .monthly
                case "yearly": return .yearly
                default: return .quarterly
                }
            } ?? .quarterly,
            ruleWeek: ruleWeekRaw.flatMap { RuleWeek(rawValue: $0) } ?? .w1,
            ruleWeekday: ruleWeekdayRaw.flatMap { RuleWeekday(rawValue: $0) } ?? .mon,
            firstTriggerAt: anchor,
            nextTriggerAt: anchor
        )

        await MainActor.run {
            modelContext.insert(reminder)
            try? modelContext.save()
            // 用引擎重算 nextTriggerAt（日期/规则类按目标月日计算，避免落到 +1 分钟）
            reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: now, reminder: reminder)
            try? modelContext.save()
            // v1.9.6 fix: 漏 touchLocalChange → AI 新建的提醒永远不同步 / 被远程旧数据覆盖
            SyncStore.touchLocalChange()
        }

        await ReminderEngine.shared.scheduleAllNotifications(for: reminder)

        return Localized("已创建提醒：「%@」", title)
    }

    private func handleList() async -> String {
        let list = await MainActor.run {
            reminders.map { " · \($0.title) [\($0.dateDisplayText)] — \($0.status.rawValue)" }
        }
        if list.isEmpty { return "当前没有提醒。" }
        return Localized("当前共有 %d 个提醒：\n%@", list.count, list.joined(separator: "\n"))
    }

    private func handleConfirm(args: [String: Any]) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        // 空关键词 contains("") 恒 true 会命中第一条无关提醒 → 必须守卫
        guard !keyword.isEmpty else { return "请指定要确认的提醒标题（如：确认「交房租」）。" }
        guard let match = await MainActor.run(body: { reminders.first(where: { $0.title.lowercased().contains(keyword) }) })
        else { return Localized("未找到包含「%@」的提醒", keyword) }

        await MainActor.run { ReminderEngine.shared.confirmReminder(match) }
        return Localized("已确认「%@」，下次提醒时间已更新。", match.title)
    }

    private func handleSnooze(args: [String: Any]) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard !keyword.isEmpty else { return "请指定要推迟的提醒标题（如：推迟「交房租」）。" }
        guard let match = await MainActor.run(body: { reminders.first(where: { $0.title.lowercased().contains(keyword) }) })
        else { return Localized("未找到包含「%@」的提醒", keyword) }

        await MainActor.run { ReminderEngine.shared.snoozeReminder(match) }
        return Localized("已推迟「%@」，15 分钟后再次提醒。", match.title)
    }

    private func handleDelete(args: [String: Any]) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard !keyword.isEmpty else { return "请指定要删除的提醒标题（如：删除「交房租」）。" }
        guard let match = await MainActor.run(body: { reminders.first(where: { $0.title.lowercased().contains(keyword) }) })
        else { return Localized("未找到包含「%@」的提醒", keyword) }

        let title = match.title
        await MainActor.run {
            modelContext.delete(match)
            try? modelContext.save()
            // v1.9.6 fix: 漏 touchLocalChange → AI 删除的提醒在远程仍然存在
            SyncStore.touchLocalChange()
        }
        // 删除前必须取消已排期的本地通知，否则到点仍会弹出（幽灵通知）
        await NotificationManager.shared.removePendingNotification(for: match.id)
        return Localized("已删除「%@」", title)
    }

    private func nearestFuture() -> Date {
        Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant || message.role == .system {
                avatar(systemName: "sparkles", color: ThemeTokens.brandPrimary)
                bubbleContent
                    // v1.9.8 设计图风格：AI 白底 + 左上尖角 + 轻阴影
                    .background(Color.white)
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 6, bottomLeading: 18, bottomTrailing: 18, topTrailing: 18),
                            style: .continuous
                        )
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                bubbleContent
                    // v1.9.8 设计图风格：用户紫渐变 + 右上尖角
                    .background(
                        LinearGradient(
                            colors: [ThemeTokens.brandGradientStart, ThemeTokens.brandPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 18, topTrailing: 6),
                            style: .continuous
                        )
                    )
                    .shadow(color: ThemeTokens.brandPrimary.opacity(0.25), radius: 6, y: 3)
                avatar(systemName: "person.circle.fill", color: .blue)
            }
        }
        .padding(.vertical, 2)
    }

    private var bubbleContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundStyle(message.role == .user ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    private func avatar(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
    }
}
