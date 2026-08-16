import SwiftUI
import SwiftData

// MARK: - Chat 消息模型
// v2.4.6: ChatMessage / ToolStep / ChatHistoryStore 已提取到 Services/ChatHistoryStore.swift（模型与 View 解耦）

// MARK: - AI 对话页面

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AISettings.shared
    @StateObject private var voice = VoiceRecognizer.shared

    // v2.4.2: 进入恢复历史对话
    @State private var messages: [ChatMessage] = ChatHistoryStore.load()
    // v2.4.2: 查看历史 → 滚动到底部触发器
    @State private var historyScrollTrigger = 0
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scrollToID: UUID?
    @State private var importPreview: ImportPreview?

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
                // v2.4.3: 消息变化即持久化（v2.4.2 只 load 没 save——历史永远空的根因）
                .onChange(of: messages) { _, newValue in
                    ChatHistoryStore.save(newValue)
                }
                // v2.4.2: 查看历史 → 滚到底部
                .onChange(of: historyScrollTrigger) { _ in
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
            // v2.4.2: 历史记录下拉（查看/清空）
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        historyScrollTrigger += 1
                    } label: {
                        Label(String(format: "查看历史（%d 条）".localized, messages.count), systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(messages.isEmpty)
                    Button(role: .destructive) {
                        messages = []
                        ChatHistoryStore.clear()
                    } label: {
                        Label("清空历史".localized, systemImage: "trash")
                    }
                    .disabled(messages.isEmpty)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ThemeTokens.brandPrimary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AISettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .onAppear {
            // v2.4.3 fix: 加 messages.isEmpty 守卫——否则每次进入都追加一条欢迎语，
            // 且被 onChange 持久化后越积越多；有历史记录时也不再打断
            if !settings.isConfigured && messages.isEmpty {
                let guide = "👋 你好！请先在右上角设置中配置 API Key（支持 DeepSeek / 通义千问 / 豆包等，均有免费额度）。\n\n我能帮你：\n• 创建提醒「每天提醒我喝水」\n• 查看列表「有什么提醒」\n• 确认完成「确认喝水」\n• 修改提醒「把交房租改成每月5号」\n• 推迟/删除提醒"
                messages.append(ChatMessage(
                    role: .assistant,
                    content: guide,
                    timestamp: Date()
                ))
            }
        }
        .sheet(item: $importPreview) { preview in
            importPreviewSheet(preview)
        }
    }

    // MARK: - 批量导入预览

    @ViewBuilder
    private func importPreviewSheet(_ preview: ImportPreview) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(preview.items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.body.weight(.medium))
                            Text(describeReminder(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !item.note.isEmpty {
                                Text(item.note)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(Localized("共解析出 %d 条提醒", preview.items.count))
                } footer: {
                    Text("确认后将一次性创建并安排通知。".localized)
                }
            }
            .navigationTitle("批量创建预览".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".localized) { importPreview = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认创建".localized) {
                        let items = preview.items
                        importPreview = nil
                        Task {
                            await commitImport(items)
                            await MainActor.run {
                                messages.append(ChatMessage(
                                    role: .assistant,
                                    content: Localized("✅ 已批量创建 %d 条提醒。", items.count),
                                    timestamp: Date()
                                ))
                            }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(ThemeTokens.brandPrimary)
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
                                : ThemeTokens.brandPrimary
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                .accessibilityLabel("发送".localized)
                .accessibilityIdentifier("send-button")
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

    // MARK: - Chat Loop（v2.2.0：Agent 多步循环 + 流式输出 + 备用降级 + 调用日志）

    private func chatLoop(userText: String) async {
        var conversation: [AIService.ChatMessage] = [
            .init(role: "system", content: AITools.systemPrompt),
            .init(role: "user", content: userText)
        ]

        var maxTurns = 5
        let startedAt = Date()
        var usedFallback = false
        var finalUsage: AIService.Usage?

        while maxTurns > 0 {
            maxTurns -= 1

            do {
                // v2.2.0: 流式只在后续轮次启用（首轮大概率是工具调用，保持非流式；
                // 工具调用后的最终文本轮次流式输出——工程取舍，可面试展开）
                let streamEnabled = maxTurns < 4
                let reply = try await AIService.shared.chatWithFallback(
                    settings: settings,
                    messages: conversation,
                    onStream: streamEnabled ? { delta in
                        Task { @MainActor in
                            if let last = messages.last, last.role == .assistant {
                                messages[messages.count - 1] = ChatMessage(
                                    role: .assistant,
                                    content: last.content + delta,
                                    timestamp: last.timestamp
                                )
                            } else {
                                messages.append(ChatMessage(role: .assistant, content: delta, timestamp: Date()))
                            }
                        }
                    } : nil
                )
                usedFallback = reply.usedFallback
                finalUsage = reply.usage

                // 有 tool_calls → 执行工具后继续（Agent 步骤可视化）
                if let toolCalls = reply.toolCalls, !toolCalls.isEmpty {
                    var steps: [ToolStep] = []
                    for tc in toolCalls {
                        steps.append(ToolStep(name: tc.function.name, status: "running", summary: nil))
                        await MainActor.run {
                            messages.append(ChatMessage(role: .assistant, content: "", timestamp: Date(), toolSteps: steps))
                        }
                        let result = await executeTool(name: tc.function.name, args: tc.function.arguments)
                        let isError = result == "参数解析失败" || result.hasPrefix("未知工具")
                        steps[steps.count - 1] = ToolStep(
                            name: tc.function.name,
                            status: isError ? "error" : "done",
                            summary: String(result.prefix(80))
                        )
                        await MainActor.run {
                            messages.append(ChatMessage(role: .assistant, content: "", timestamp: Date(), toolSteps: steps))
                        }
                        conversation.append(.init(role: "assistant", tool_calls: [tc]))
                        conversation.append(.init(role: "tool", content: result, tool_call_id: tc.id))
                    }
                    // 步骤气泡由最终回复接管
                    await MainActor.run {
                        messages.removeAll { !$0.toolSteps.isEmpty }
                    }
                    continue
                }

                // 纯文本回复（流式已增量上屏；非流式兜底）
                var content = reply.content ?? "好的，已处理。"
                if reply.finishReason == "length" {
                    content += "\n\n（响应长度受限，已截断）"
                }
                if !content.isEmpty && messages.last?.content != content {
                    await MainActor.run {
                        if let last = messages.last, last.role == .assistant, !last.content.isEmpty {
                            messages[messages.count - 1] = ChatMessage(
                                role: .assistant,
                                content: content,
                                timestamp: last.timestamp
                            )
                        } else {
                            messages.append(ChatMessage(role: .assistant, content: content, timestamp: Date()))
                        }
                        isLoading = false
                    }
                } else {
                    await MainActor.run { isLoading = false }
                }

                AILogStore.add(AILogStore.Entry(
                    model: usedFallback ? settings.fallbackModel : settings.model,
                    provider: usedFallback ? "fallback" : "primary",
                    turns: 5 - maxTurns,
                    promptTokens: finalUsage?.prompt_tokens,
                    completionTokens: finalUsage?.completion_tokens,
                    durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                    ok: true
                ))
                return

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
                AILogStore.add(AILogStore.Entry(
                    model: usedFallback ? settings.fallbackModel : settings.model,
                    provider: usedFallback ? "fallback" : "primary",
                    turns: 5 - maxTurns,
                    durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                    ok: false,
                    error: error.localizedDescription
                ))
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
        case "update_reminder":
            return await handleUpdate(args: args)
        case "import_tasks":
            return await handleImportTasks(args: args)
        default:
            return Localized("未知工具: %@", name)
        }
    }

    // MARK: - Tool Handlers

    // 解析工具参数 → 构造 Reminder。返回 (reminder, nil) 成功；(nil, errorMessage) 校验失败。
    // handleCreate 与 import_tasks 共用，避免重复解析逻辑。
    private func buildReminder(from args: [String: Any]) -> (Reminder?, String?) {
        let title = args["title"] as? String ?? "未命名提醒"
        let kind = args["kind"] as? String ?? "cycle"
        let note = args["note"] as? String ?? ""
        let cycle = args["cycle"] as? String ?? "weekly"
        let customDays = args["custom_days"] as? Int ?? 0
        // C2: AI 创建 custom 周期必须 customDays>=1（对齐 Android handleCreate 守卫），否则 interval=0 → 确认后死循环
        if cycle == "custom", customDays < 1 {
            return (nil, "自定义周期需要指定间隔天数（如：每3天），custom_days 至少为 1。")
        }
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

        // v2.4.2: 每周意图星期（1=周一..7=周日）——模型对「每周日」这类周期描述
        // 往往不传 trigger_date，必须靠 weekday 对齐锚点（根治每周错位）
        let weekdayParam = (args["weekday"] as? Int)
            ?? (args["weekday"] as? Double).map(Int.init)
            ?? (args["weekday"] as? String).flatMap(Int.init)

        // 日期类提醒必须带合法月日，否则引擎算不出正确触发时间。
        // 与其创建一个会误触发的提醒，不如让用户补一句。
        if kind == "date" {
            if dateType == "holiday" {
                if (holidayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    return (nil, "需要指定节假日名称（例如：春节、中秋节）才能创建节假日提醒。")
                }
            } else if !(1...12).contains(targetMonth) || !(1...31).contains(targetDay) {
                return (nil, "需要具体的公历/农历月日才能创建日期提醒（例如：农历八月十五、公历5月1日）。请补充月日，我再为你创建。")
            }
        }
        // v1.9.0 fix: 规则提醒必须带全 频率/第几周/周几
        if kind == "rule" {
            guard let rp = rulePeriodRaw, let rw = ruleWeekRaw, let rwd = ruleWeekdayRaw else {
                return (nil, "规则提醒需要指定频率（每月/每季度/每年）、第几周和星期几，例如：每季度第一周周四。请补充完整，我再为你创建。")
            }
            guard ["monthly", "quarterly", "yearly"].contains(rp),
                  (1...5).contains(rw), (1...7).contains(rwd) else {
                return (nil, "规则提醒参数不合法：频率应为每月/每季度/每年，第几周 1-5，星期几 1=周一...7=周日。")
            }
        }

        let now = Date()
        // 首次锚点（优先级）：
        // 1) weekly/biweekly 且 AI 传了 weekday → 对齐到下一个该星期的 reminderHour:Minute
        //    （今天就是且未过 → 今天）。v2.4.2 根治：模型对周期描述常不传 trigger_date。
        // 2) AI 明确给了 trigger_date → 用它 + reminderHour/Minute（v2.4.1）。
        // 3) 默认 → 下一个到达 reminderHour:reminderMinute 的时刻（今天已过则明天）。
        var anchor = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now) ?? now
        if (cycle == "weekly" || cycle == "biweekly"), let wd = weekdayParam, (1...7).contains(wd) {
            let cal = Calendar.current
            let cur = ((cal.component(.weekday, from: anchor) + 5) % 7) + 1  // 1=周一..7=周日
            var diff = (wd - cur + 7) % 7
            if diff == 0 && anchor <= now { diff = 7 }
            anchor = cal.date(byAdding: .day, value: diff, to: anchor) ?? anchor
        } else {
            if let dateStr = args["trigger_date"] as? String {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: dateStr.trimmingCharacters(in: .whitespaces)),
                   d > now {
                    anchor = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: d) ?? d
                }
            }
            if anchor <= now { anchor = Calendar.current.date(byAdding: .day, value: 1, to: anchor) ?? anchor }
        }

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
            case "custom":    return .custom
            default:          return .weekly
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
        return (reminder, nil)
    }

    private func handleCreate(args: [String: Any]) async -> String {
        let (reminder, err) = buildReminder(from: args)
        guard let reminder else { return err ?? "创建失败" }
        await MainActor.run {
            modelContext.insert(reminder)
            try? modelContext.save()
            // v2.4.2: 存意图星期（锚点错位检测/修正用）——weekly/biweekly 存锚点星期
            // （buildReminder 内 weekdayParam 对齐过锚点，此处从锚点反推即为意图星期）
            if reminder.cycle == .weekly || reminder.cycle == .biweekly {
                let anchorDow = ((Calendar.current.component(.weekday, from: reminder.firstTriggerAt) + 5) % 7) + 1
                WeeklyWeekdayStore.set(anchorDow, for: reminder.id)
            } else {
                WeeklyWeekdayStore.set(nil, for: reminder.id)
            }
            // 用引擎重算 nextTriggerAt（日期/规则类按目标月日计算，避免落到 +1 分钟）
            reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: reminder)
            try? modelContext.save()
            // v1.9.6 fix: 漏 touchLocalChange → AI 新建的提醒永远不同步 / 被远程旧数据覆盖
            SyncStore.touchLocalChange()
        }
        await ReminderEngine.shared.scheduleAllNotifications(for: reminder)
        return Localized("已创建提醒：「%@」", reminder.title)
    }

    /// import_tasks 工具：把多段待办解析为多条提醒，挂起预览弹窗等用户确认。
    /// 不直接写入数据库——确认逻辑在 commitImport（用户点「确认创建」时调用）。
    private func handleImportTasks(args: [String: Any]) async -> String {
        guard let items = args["items"] as? [[String: Any]], !items.isEmpty else {
            return "没有解析到可批量创建的提醒。"
        }
        var built: [Reminder] = []
        var skipped = 0
        var skippedReasons: [String] = []
        for item in items {
            // I24: 透传 buildReminder 校验失败原因，避免静默计入 skipped 让用户不知为何被跳过
            let (r, err) = buildReminder(from: item)
            if let r { built.append(r) } else { skipped += 1; skippedReasons.append(err ?? "格式无法识别") }
        }
        guard !built.isEmpty else {
            return "解析失败：所有条目都无法识别为有效提醒。"
        }
        await MainActor.run { importPreview = ImportPreview(items: built) }
        var preview = Localized("已解析出 %d 条提醒，请确认后批量创建：", built.count)
        for (i, r) in built.enumerated() {
            preview += "\n\(i + 1). \(r.title) 〔\(describeReminder(r))〕"
        }
        if skipped > 0 {
            preview += "\n（\(skipped) 条无法解析已跳过："
            preview += skippedReasons.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "；")
            preview += "）"
        }
        return preview
    }

    private func describeReminder(_ r: Reminder) -> String {
        switch r.kind {
        case .date:  return r.dateDisplayText
        case .rule:  return r.cycle.rawValue
        case .cycle: return r.cycle.rawValue
        }
    }

    /// 用户确认预览后批量写入：逐条 insert + 调度 + 标记本地变更
    private func commitImport(_ items: [Reminder]) async {
        await MainActor.run {
            for r in items { modelContext.insert(r) }
            try? modelContext.save()
            // I1: 批量导入按提醒类型重算 nextTriggerAt（日期类按目标月日、规则类按第N周周X，
            // 避免 buildReminder 的泛型锚点导致错日触发——对齐 handleCreate 单条路径）
            for r in items {
                r.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: r)
            }
            try? modelContext.save()
            SyncStore.touchLocalChange()
        }
        for r in items {
            await ReminderEngine.shared.scheduleAllNotifications(for: r)
        }
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

        await MainActor.run { ReminderEngine.shared.snoozeReminder(match, afterMinutes: 15) }
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

    private func handleUpdate(args: [String: Any]) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard !keyword.isEmpty else { return "请指定要修改的提醒标题（如：把「交房租」改成每月 5 号）。" }

        // 预处理参数（custom 周期必须 custom_days >= 1）
        let cycleRaw = args["cycle"] as? String
        let customDaysRaw = (args["custom_days"] as? Int) ?? (args["custom_days"] as? Double).map(Int.init)

        guard let match = await MainActor.run(body: { reminders.first(where: { $0.title.lowercased().contains(keyword) }) })
        else { return Localized("未找到包含「%@」的提醒", keyword) }

        // C3: 用「生效后的周期」判断，而非「本次传入的周期」——
        // 提醒已是 custom 时，模型只传 custom_days:0 而不传 cycle，旧守卫(cycleRaw=="custom")会被绕过，落入 C2 后果链
        // D2: 未传 custom_days 不算「传了 0」——已建 custom 提醒只改标题/时间时应放行
        // （Android `?: match.customDays` 保留原值不受影响，iOS 需显式判 nil）
        // I2: 显式切到 custom 周期但缺/非法 custom_days 时拒绝（镜像创建路径守卫），
        //     避免 customDays 留旧值(常0)导致 calculateNextCycleTrigger 返回过去锚点、提醒永不触发；
        //     已为 custom 且只改标题/时间（未传 cycle）放行 → 仅当 cycleRaw=="custom" 才拦截
        if cycleRaw == "custom", (customDaysRaw ?? 0) < 1 {
            return "自定义周期需要指定间隔天数（如：每3天），custom_days 至少为 1。"
        }

        let updatedTitle = await MainActor.run {
            // 字符串字段
            if let nt = args["new_title"] as? String { match.title = nt }
            if let n = args["note"] as? String { match.note = n }

            // 周期 + 自定义天数
            if let c = cycleRaw {
                switch c {
                case "once":      match.cycle = .once
                case "daily":     match.cycle = .daily
                case "weekly":    match.cycle = .weekly
                case "biweekly":  match.cycle = .biweekly
                case "monthly":   match.cycle = .monthly
                case "quarterly": match.cycle = .quarterly
                case "yearly":    match.cycle = .yearly
                case "custom":    match.cycle = .custom
                default: break
                }
            }
            if let cd = customDaysRaw { match.customDays = cd }

            // 规则参数（第N周周X）
            if let rp = args["rule_period"] as? String {
                switch rp {
                case "monthly": match.rulePeriod = .monthly
                case "yearly": match.rulePeriod = .yearly
                default: match.rulePeriod = .quarterly
                }
            }
            if let rw = (args["rule_week"] as? Int) ?? (args["rule_week"] as? Double).map(Int.init),
               let w = RuleWeek(rawValue: rw) { match.ruleWeek = w }
            if let rwd = (args["rule_weekday"] as? Int) ?? (args["rule_weekday"] as? Double).map(Int.init),
               let wd = RuleWeekday(rawValue: rwd) { match.ruleWeekday = wd }

            // 日期类参数
            if let dt = args["date_type"] as? String {
                switch dt {
                case "solar_birthday": match.dateType = .solarBirthday
                case "lunar_birthday": match.dateType = .lunarBirthday
                case "holiday":        match.dateType = .holiday
                default: break
                }
            }
            if let tm = (args["target_month"] as? Int) ?? (args["target_month"] as? Double).map(Int.init) {
                match.targetMonth = tm
            }
            if let td = (args["target_day"] as? Int) ?? (args["target_day"] as? Double).map(Int.init) {
                match.targetDay = td
            }
            if let hn = args["holiday_name"] as? String {
                match.holidayID = HolidayService.search(by: hn)?.id
            }

            // 提前 / 时分
            if let ah = (args["advance_days"] as? Int) ?? (args["advance_days"] as? Double).map(Int.init) {
                match.advanceDays = ah
            }
            let hasHour = (args["reminder_hour"] as? Int) != nil || (args["reminder_hour"] as? Double) != nil
            let hasMinute = (args["reminder_minute"] as? Int) != nil || (args["reminder_minute"] as? Double) != nil
            if let rh = (args["reminder_hour"] as? Int) ?? (args["reminder_hour"] as? Double).map(Int.init) {
                match.reminderHour = rh
            }
            if let rm = (args["reminder_minute"] as? Int) ?? (args["reminder_minute"] as? Double).map(Int.init) {
                match.reminderMinute = rm
            }

            // Bug 3: cycle 类需同步改写锚点时分，否则 AI 改提醒时间对 cycle 无效
            // （date/rule 分支已用 comps.hour = reminderHour，仅 cycle 走 firstTriggerAt 锚点）
            // A7: 仅当本次 AI 真传了时分字段才重写锚点，避免「只改标题」也被对齐一次、静默改变触发时分
            if match.kind == .cycle, match.cycle != .once, (hasHour || hasMinute) {
                var anchorComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: match.firstTriggerAt)
                anchorComps.hour = match.reminderHour
                anchorComps.minute = match.reminderMinute
                anchorComps.second = 0
                if let newAnchor = Calendar.current.date(from: anchorComps) {
                    match.firstTriggerAt = newAnchor
                }
            }

            // C1: AI 修改已逾期提醒时，必须重新激活状态——否则下方 scheduleAllNotifications 的
            // 幽灵守卫(status==.overdue 直接 return)会拦掉全部通知，导致「AI 说改好了，提醒却永久不响」
            if match.status == .overdue {
                match.status = .pending
                match.retryStage = 0
                match.lastRetryAt = nil
            }

            // 重算下次触发时间（按新参数）并保存
            match.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: Date(), reminder: match)
            // Item 2: 参数变更后清空旧的前移备注（避免误显示）
            ReminderEngine.HolidayAdjustStore.setNote(nil, for: match.id)
            try? modelContext.save()
            SyncStore.touchLocalChange()
            return match.title
        }

        // 重排本地通知
        await ReminderEngine.shared.scheduleAllNotifications(for: match)
        return Localized("已修改「%@」", updatedTitle)
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
                    // v2.0.22: AI 气泡改系统表面色——原固定白色在深色模式下刺眼，
                    // 与玻璃卡片和整体背景不一致
                    .background(Color(.secondarySystemBackground))
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
                avatar(systemName: "person.circle.fill", color: ThemeTokens.brandPrimary)
            }
        }
        .padding(.vertical, 2)
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // v2.2.0: Agent 工具步骤可视化（执行中 → 完成/失败）
            if !message.toolSteps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.toolSteps) { step in
                        HStack(spacing: 8) {
                            Group {
                                switch step.status {
                                case "running":
                                    ProgressView()
                                        .controlSize(.mini)
                                case "error":
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(ThemeTokens.statusOverdue)
                                default:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ThemeTokens.statusCompleted)
                                }
                            }
                            .frame(width: 16)
                            Text(step.name)
                                .font(.caption.weight(.medium))
                            if step.status == "running" {
                                Text("执行中…".localized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            Text(message.content)
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private func avatar(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
    }
}

// MARK: - 批量导入预览载体

/// AI 用 import_tasks 解析出的待创建提醒列表（尚未写入 modelContext）。
/// 用户在预览弹窗点「确认创建」后才批量落库。
struct ImportPreview: Identifiable {
    let id = UUID()
    let items: [Reminder]
}
