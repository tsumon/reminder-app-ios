import SwiftUI
import SwiftData
import WebKit

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
    @State private var showNoAPISheet = false
    @State private var webURL: URL?
    @State private var showWebView = false

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
                                if settings.useNoAPIMode {
                                    noAPILoadingView
                                } else {
                                    ProgressView()
                                        .padding(12)
                                }
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

            // 底部输入栏
            inputBar
        }
        .navigationTitle(settings.useNoAPIMode ? "AI 助手 · 免 API" : "AI 助手")
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
        .confirmationDialog("选择 AI 服务", isPresented: $showNoAPISheet, titleVisibility: .visible) {
            ForEach(ExternalAppService.Provider.allCases) { p in
                Button("\(p.name)") {
                    ExternalAppService.openWeb(for: p, withText: inputText)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("文字已复制到剪贴板，选择服务后将在网页中粘贴发送。")
        }
        .sheet(isPresented: $showWebView) {
            if let url = webURL {
                WebViewSheet(url: url)
            }
        }
        .onAppear {
            if !settings.isConfigured {
                let guide = settings.useNoAPIMode
                    ? "👋 免 API 模式已开启！\n\n输入提醒需求后，会自动复制文字并跳转到网页版 AI，在那里粘贴发送即可。\n\n我能帮你：\n• 创建提醒「每天提醒我喝水」\n• 查看列表「有什么提醒」\n• 确认完成「确认喝水」\n• 推迟/删除提醒"
                    : "👋 你好！请先在右上角设置中配置 API Key，或者开启「免 API 模式」无需 Key 直接使用。\n\n我能帮你：\n• 创建提醒「每天提醒我喝水」\n• 查看列表「有什么提醒」\n• 确认完成「确认喝水」\n• 推迟/删除提醒"
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
            Image(systemName: settings.useNoAPIMode ? "bolt.fill" : "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(settings.useNoAPIMode ? .orange : .purple)
                .padding(.top, 40)
            Text(settings.useNoAPIMode ? "免 API 模式" : "跟我说你想提醒什么")
                .font(.title3.weight(.semibold))
            if settings.useNoAPIMode {
                Text("输入需求 → 自动跳转网页版 AI\n粘贴即用，无需 Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("\"每天8点提醒我吃药\"\n\"每年提醒我妈生日\"\n\"每周一早上开会\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer().frame(height: 40)
        }
    }

    // MARK: - No-API loading

    private var noAPILoadingView: some View {
        VStack(spacing: 8) {
            Text("文字已复制，正在跳转...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
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
                TextField("输入或点击麦克风说话...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .disabled(isLoading)

                // 发送按钮（免 API 模式下也允许发送）
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
                                ? .gray
                                : (settings.useNoAPIMode ? .orange : .purple)
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

        // ── 免 API 模式：复制 + 跳转网页 ──
        if settings.useNoAPIMode {
            messages.append(ChatMessage(role: .user, content: text, timestamp: Date()))
            let savedText = text
            inputText = ""
            errorMessage = nil

            // 复制到剪贴板
            UIPasteboard.general.string = savedText

            let provider = ExternalAppService.Provider.allCases.first(where: { $0.rawValue == settings.noAPIProvider })
                ?? .deepseek

            isLoading = false
            messages.append(ChatMessage(
                role: .assistant,
                content: "⚠️ 已复制「\(savedText.prefix(30))\(savedText.count > 30 ? "..." : "")」到剪贴板，并在应用内打开了「\(provider.name)」网页，请直接粘贴发送。\n\n若网页未自动弹出，也可手动打开：\(provider.webURL.absoluteString)",
                timestamp: Date()
            ))

            // 应用内打开网页（修复「免 API 模式切换到网页对话无法返回」）
            webURL = provider.webURL
            showWebView = true
            return
        }

        // ── API 模式 ──
        guard settings.isConfigured else { return }

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
            return "未知工具: \(name)"
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

        let now = Date()
        // 首次锚点：下一个到达 reminderHour:reminderMinute 的时刻（cycle 用作周期锚点）
        var anchor = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: now) ?? now
        if anchor <= now { anchor = Calendar.current.date(byAdding: .day, value: 1, to: anchor) ?? anchor }

        var holidayID: String? = nil
        if let hn = holidayName {
            holidayID = HolidayService.search(by: hn)?.id
        }

        let reminderKind: ReminderKind = kind == "date" ? .date : .cycle
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
            firstTriggerAt: anchor,
            nextTriggerAt: anchor
        )

        await MainActor.run {
            modelContext.insert(reminder)
            try? modelContext.save()
            // 用引擎重算 nextTriggerAt（日期/规则类按目标月日计算，避免落到 +1 分钟）
            reminder.nextTriggerAt = ReminderEngine.shared.calculateNextTrigger(after: now, reminder: reminder)
            try? modelContext.save()
        }

        await ReminderEngine.shared.scheduleAllNotifications(for: reminder)

        return "已创建提醒：「\(title)」"
    }

    private func handleList() async -> String {
        let list = await MainActor.run {
            reminders.map { " · \($0.title) [\($0.dateDisplayText)] — \($0.status.rawValue)" }
        }
        if list.isEmpty { return "当前没有提醒。" }
        return "当前共有 \(list.count) 个提醒：\n\(list.joined(separator: "\n"))"
    }

    private func handleConfirm(args: [String: Any]) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard let match = await MainActor.run(body: { reminders.first(where: { $0.title.lowercased().contains(keyword) }) })
        else { return "未找到包含「\(keyword)」的提醒" }

        await MainActor.run { ReminderEngine.shared.confirmReminder(match) }
        return "已确认「\(match.title)」，下次提醒时间已更新。"
    }

    private func handleSnooze(args: [String: Any]) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard let match = await MainActor.run(body: { reminders.first(where: { $0.title.lowercased().contains(keyword) }) })
        else { return "未找到包含「\(keyword)」的提醒" }

        await MainActor.run { ReminderEngine.shared.snoozeReminder(match) }
        return "已推迟「\(match.title)」，15 分钟后再次提醒。"
    }

    private func handleDelete(args: [String: Any]) async -> String {
        let keyword = (args["title_keyword"] as? String ?? "").lowercased()
        guard let match = await MainActor.run(body: { reminders.first(where: { $0.title.lowercased().contains(keyword) }) })
        else { return "未找到包含「\(keyword)」的提醒" }

        let title = match.title
        await MainActor.run { modelContext.delete(match); try? modelContext.save() }
        return "已删除「\(title)」"
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
                avatar(systemName: "sparkles", color: .purple)
                bubbleContent
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                bubbleContent
                    .background(Color.purple.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
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

// MARK: - 应用内网页浏览器（修复免 API 模式「无法返回」）

struct WebViewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("网页 AI 助手")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                    }
                }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
