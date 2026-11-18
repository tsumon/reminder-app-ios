import Foundation
import SwiftData

/// AI 批量创建预览载体
struct ImportPreview: Identifiable {
    let id = UUID()
    let items: [Reminder]
}

/// AI 对话视图模型：抽离历史持久化、流式 Agent 循环与 ask_user 拦截
@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = ChatHistoryStore.load() {
        didSet {
            ChatHistoryStore.save(messages)
        }
    }
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var importPreview: ImportPreview?

    func syncOnAppear(isConfigured: Bool) {
        let stored = ChatHistoryStore.load()
        if stored != messages {
            messages = stored
        }
        if !isConfigured && messages.isEmpty {
            let guide = "👋 你好！请先在右上角设置中配置 API Key（支持 DeepSeek / 通义千问 / 豆包等，均有免费额度）。\n\n我能帮你：\n• 创建提醒「每天提醒我喝水」\n• 查看列表「有什么提醒」\n• 确认完成「确认喝水」\n• 修改提醒「把交房租改成每月5号」\n• 推迟/删除提醒"
            messages.append(ChatMessage(role: .assistant, content: guide, timestamp: Date()))
        }
    }

    func clearHistory() {
        messages = []
        ChatHistoryStore.clear()
    }

    func sendMessage(settings: AISettings, context: ModelContext) {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard settings.isConfigured else {
            errorMessage = "请先在右上角设置中配置 API Key"
            return
        }
        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text, timestamp: Date()))
        isLoading = true
        Task { await chatLoop(userText: text, settings: settings, context: context) }
    }

    func sendWeeklyInsight(settings: AISettings, context: ModelContext) {
        guard settings.isConfigured else {
            errorMessage = "请先在右上角设置中配置 API Key"
            return
        }
        let text = "给我一份本周提醒总结和洞察"
        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text, timestamp: Date()))
        isLoading = true
        Task { await chatLoop(userText: text, settings: settings, context: context) }
    }

    func sendOption(_ option: String, from message: ChatMessage, settings: AISettings, context: ModelContext) {
        guard !isLoading else { return }
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx].options = nil
        }
        messages.append(ChatMessage(role: .user, content: option, timestamp: Date()))
        isLoading = true
        Task { await chatLoop(userText: option, settings: settings, context: context) }
    }

    func confirmBatchImport(_ items: [Reminder], context: ModelContext) {
        importPreview = nil
        Task {
            await AIChatToolExecutor.commitImport(items, context: context)
            messages.append(ChatMessage(
                role: .assistant,
                content: Localized("✅ 已批量创建 %d 条提醒。", items.count),
                timestamp: Date()
            ))
        }
    }

    // MARK: - Agent 多步对话循环

    func chatLoop(userText: String, settings: AISettings, context: ModelContext) async {
        var conversation: [AIService.ChatMessage] = [
            .init(role: "system", content: AITools.systemPrompt)
        ]
        let history = messages
            .filter { !$0.content.isEmpty && $0.toolSteps.isEmpty }
            .dropLast()
            .suffix(20)
            .map { AIService.ChatMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content) }
        conversation.append(contentsOf: history)
        conversation.append(.init(role: "user", content: userText))

        var maxTurns = 5
        let startedAt = Date()
        var usedFallback = false
        var finalUsage: AIService.Usage?

        while maxTurns > 0 {
            maxTurns -= 1
            do {
                let streamEnabled = maxTurns < 4
                let reply = try await AIService.shared.chatWithFallback(
                    settings: settings,
                    messages: conversation,
                    onStream: streamEnabled ? { [weak self] delta in
                        Task { @MainActor in
                            guard let self else { return }
                            if let last = self.messages.last, last.role == .assistant, last.toolSteps.isEmpty {
                                self.messages[self.messages.count - 1] = ChatMessage(
                                    role: .assistant,
                                    content: last.content + delta,
                                    timestamp: last.timestamp
                                )
                            } else {
                                self.messages.append(ChatMessage(role: .assistant, content: delta, timestamp: Date()))
                            }
                        }
                    } : nil
                )
                usedFallback = reply.usedFallback
                finalUsage = reply.usage

                if let toolCalls = reply.toolCalls, !toolCalls.isEmpty {
                    var steps: [ToolStep] = []
                    for tc in toolCalls {
                        if tc.function.name == "ask_user" {
                            var question = "请补充信息"
                            var options: [String] = []
                            if let data = tc.function.arguments.data(using: .utf8),
                               let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                if let q = args["question"] as? String, !q.isEmpty { question = q }
                                if let opts = args["options"] as? [String] {
                                    options = opts.filter { !$0.isEmpty }
                                }
                            }
                            messages.removeAll { !$0.toolSteps.isEmpty }
                            messages.append(ChatMessage(
                                role: .assistant,
                                content: question,
                                timestamp: Date(),
                                options: options.isEmpty ? nil : options
                            ))
                            isLoading = false
                            logCall(settings: settings, usedFallback: usedFallback, turns: 5 - maxTurns,
                                    usage: finalUsage, startedAt: startedAt, ok: true, error: nil)
                            return
                        }

                        steps.append(ToolStep(name: tc.function.name, status: "running", summary: nil))
                        messages.append(ChatMessage(role: .assistant, content: "", timestamp: Date(), toolSteps: steps))

                        let (result, preview) = await AIChatToolExecutor.execute(
                            name: tc.function.name,
                            argsJSON: tc.function.arguments,
                            context: context
                        )
                        if let preview {
                            importPreview = preview
                        }
                        let isErr = result == "参数解析失败" || result.hasPrefix("未知工具")
                        steps[steps.count - 1] = ToolStep(
                            name: tc.function.name,
                            status: isErr ? "error" : "done",
                            summary: String(result.prefix(80))
                        )
                        messages.append(ChatMessage(role: .assistant, content: "", timestamp: Date(), toolSteps: steps))
                        conversation.append(.init(role: "assistant", tool_calls: [tc]))
                        conversation.append(.init(role: "tool", content: result, tool_call_id: tc.id))
                    }
                    messages.removeAll { !$0.toolSteps.isEmpty }
                    continue
                }

                var content = reply.content ?? "好的，已处理。"
                if reply.finishReason == "length" {
                    content += "\n\n（响应长度受限，已截断）"
                }
                if !content.isEmpty && messages.last?.content != content {
                    if let last = messages.last, last.role == .assistant, !last.content.isEmpty {
                        messages[messages.count - 1] = ChatMessage(
                            role: .assistant,
                            content: content,
                            timestamp: last.timestamp
                        )
                    } else {
                        messages.append(ChatMessage(role: .assistant, content: content, timestamp: Date()))
                    }
                }
                isLoading = false
                logCall(settings: settings, usedFallback: usedFallback, turns: 5 - maxTurns,
                        usage: finalUsage, startedAt: startedAt, ok: true, error: nil)
                return
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                logCall(settings: settings, usedFallback: usedFallback, turns: 5 - maxTurns,
                        usage: finalUsage, startedAt: startedAt, ok: false, error: error.localizedDescription)
                return
            }
        }

        messages.append(ChatMessage(role: .assistant, content: "对话轮次过多，请重新描述你的需求。", timestamp: Date()))
        isLoading = false
    }

    private func logCall(
        settings: AISettings,
        usedFallback: Bool,
        turns: Int,
        usage: AIService.Usage?,
        startedAt: Date,
        ok: Bool,
        error: String?
    ) {
        AILogStore.add(AILogStore.Entry(
            model: usedFallback ? settings.fallbackModel : settings.model,
            provider: usedFallback ? "fallback" : "primary",
            turns: turns,
            promptTokens: usage?.prompt_tokens,
            completionTokens: usage?.completion_tokens,
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            ok: ok,
            error: error
        ))
    }
}
