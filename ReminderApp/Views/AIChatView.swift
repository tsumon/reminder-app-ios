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

            // 底部输入栏
            inputBar
        }
        .navigationTitle("AI 助手")
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
                messages.append(ChatMessage(
                    role: .assistant,
                    content: "👋 你好！请先在右上角设置中配置 API Key，然后就可以用语音或文字跟我说话了。\n\n我能帮你：\n• 创建提醒「每天提醒我喝水」\n• 查看列表「有什么提醒」\n• 确认完成「确认喝水」\n• 推迟/删除提醒",
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
            Text("跟我说你想提醒什么")
                .font(.title3.weight(.semibold))
            Text("\"每天8点提醒我吃药\"\n\"每年提醒我妈生日\"\n\"每周一早上开会\"")
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
                TextField("输入或点击麦克风说话...", text: $inputText, axis: .vertical)
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
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .purple)
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
        guard !text.isEmpty, settings.isConfigured else { return }

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
        let targetMonth = args["target_month"] as? Int ?? 1
        let targetDay = args["target_day"] as? Int ?? 1
        let advanceDays = args["advance_days"] as? Int ?? 3
        let reminderHour = args["reminder_hour"] as? Int ?? 9
        let reminderMinute = args["reminder_minute"] as? Int ?? 0
        let holidayName = args["holiday_name"] as? String

        // 解析触发日期
        let dateFormatter = DateFormatter(); dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        var firstTrigger: Date
        if let dateStr = args["trigger_date"] as? String,
           let timeStr = args["trigger_time"] as? String {
            firstTrigger = dateFormatter.date(from: "\(dateStr) \(timeStr)") ?? nearestFuture()
        } else if let dateStr = args["trigger_date"] as? String {
            firstTrigger = dateFormatter.date(from: "\(dateStr) 09:00") ?? nearestFuture()
        } else {
            firstTrigger = nearestFuture()
        }

        // 查找 holidayID
        var holidayID: String? = nil
        if let hn = holidayName {
            holidayID = HolidayService.search(by: hn)?.id
        }

        let reminderKind: ReminderKind = kind == "date" ? .date : .cycle
        let cycleEnum: ReminderCycle = {
            switch cycle {
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
            firstTriggerAt: firstTrigger,
            nextTriggerAt: firstTrigger
        )

        await MainActor.run { modelContext.insert(reminder); try? modelContext.save() }
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
