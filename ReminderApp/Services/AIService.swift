import Foundation

/// OpenAI 兼容 API 调用服务（v2.2.0：流式输出 + token 统计 + 备用降级）
actor AIService {
    static let shared = AIService()

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - 消息模型

    struct ChatMessage: Codable {
        let role: String        // "system" | "user" | "assistant" | "tool"
        let content: String?
        let tool_calls: [ToolCall]?
        let tool_call_id: String?

        init(role: String, content: String? = nil, tool_calls: [ToolCall]? = nil, tool_call_id: String? = nil) {
            self.role = role
            self.content = content
            self.tool_calls = tool_calls
            self.tool_call_id = tool_call_id
        }
    }

    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: FunctionCall
    }

    struct FunctionCall: Codable {
        let name: String
        let arguments: String   // JSON string
    }

    // v2.4.9: SSE tool_calls 分片解码器——分片可能只含部分字段（首片有 id/name，后续片只有 arguments），
    // 用 Optional 字段避免 decode 失败
    struct StreamDelta: Codable {
        let content: String?
        let tool_calls: [StreamToolCallFragment]?
    }

    struct StreamToolCallFragment: Codable {
        let index: Int?
        let id: String?
        let type: String?
        let function: StreamFunctionFragment?

        struct StreamFunctionFragment: Codable {
            let name: String?
            let arguments: String?
        }
    }

    struct StreamChoice: Codable {
        let delta: StreamDelta?
        let finish_reason: String?
    }

    struct StreamChunkResponse: Codable {
        let choices: [StreamChoice]?
        let usage: Usage?
    }

    struct Usage: Codable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }

    /// 一次完整对话的结果（含流式累积文本、工具调用、token 用量、实际使用的 provider）
    struct ChatResult {
        let content: String?
        let toolCalls: [ToolCall]?
        let usage: Usage?
        let finishReason: String?
        let usedFallback: Bool
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let tools: [[String: AnyCodable]]?
        let tool_choice: String?
        let stream: Bool?
        let stream_options: [String: Bool]?

        enum CodingKeys: String, CodingKey {
            case model, messages, tools, stream
            case tool_choice
            case stream_options
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(model, forKey: .model)
            try c.encode(messages, forKey: .messages)
            if let t = tools { try c.encode(t, forKey: .tools) }
            if let tc = tool_choice { try c.encode(tc, forKey: .tool_choice) }
            if let s = stream { try c.encode(s, forKey: .stream) }
            if let so = stream_options { try c.encode(so, forKey: .stream_options) }
        }
    }

    struct ChatResponse: Codable {
        let choices: [Choice]
        let usage: Usage?
    }

    struct Choice: Codable {
        let message: ChatMessage?
        let delta: ChatMessage?
        let finish_reason: String?
    }

    // MARK: - Public

    /// 聊天（带工具）：主配置失败且配置了备用时自动降级重试一次。
    /// stream 模式下只对纯文本回复做增量输出（工具调用轮次保持非流式）。
    func chatWithFallback(
        settings: AISettings,
        messages: [ChatMessage],
        onStream: ((String) -> Void)? = nil
    ) async throws -> ChatResult {
        do {
            return try await chat(
                model: settings.model,
                messages: messages,
                endpoint: settings.apiEndpoint,
                apiKey: settings.apiKey,
                onStream: onStream
            )
        } catch {
            guard settings.hasFallback else { throw error }
            // 主配置失败 → 备用降级（带一次退避）
            try? await Task.sleep(nanoseconds: 500_000_000)
            do {
                var result = try await chat(
                    model: settings.fallbackModel,
                    messages: messages,
                    endpoint: settings.fallbackEndpoint,
                    apiKey: settings.fallbackKey,
                    onStream: onStream
                )
                result = ChatResult(
                    content: result.content,
                    toolCalls: result.toolCalls,
                    usage: result.usage,
                    finishReason: result.finishReason,
                    usedFallback: true
                )
                return result
            } catch {
                throw error  // 备用也失败 → 抛主错误还是备用错误？抛备用错误（信息更新）
            }
        }
    }

    /// 纯文本补全（不带 tools）——用于周报 AI 解读；同样支持备用降级
    func completeWithFallback(
        settings: AISettings,
        messages: [ChatMessage]
    ) async throws -> String {
        do {
            return try await complete(
                model: settings.model,
                messages: messages,
                endpoint: settings.apiEndpoint,
                apiKey: settings.apiKey
            )
        } catch {
            guard settings.hasFallback else { throw error }
            try? await Task.sleep(nanoseconds: 500_000_000)
            return try await complete(
                model: settings.fallbackModel,
                messages: messages,
                endpoint: settings.fallbackEndpoint,
                apiKey: settings.fallbackKey
            )
        }
    }

    func chat(
        model: String,
        messages: [ChatMessage],
        endpoint: String,
        apiKey: String,
        onStream: ((String) -> Void)? = nil
    ) async throws -> ChatResult {
        if onStream != nil {
            return try await streamSend(model: model, messages: messages, endpoint: endpoint, apiKey: apiKey, useTools: true, onStream: onStream!)
        }
        return try await send(model: model, messages: messages, endpoint: endpoint, apiKey: apiKey, useTools: true)
    }

    /// 纯文本补全（不带 tools）——用于周报 AI 解读这类「只要一段话」的场景，
    /// 避免模型误触发 function call 导致返回 content 为空。
    func complete(
        model: String,
        messages: [ChatMessage],
        endpoint: String,
        apiKey: String
    ) async throws -> String {
        let result = try await send(model: model, messages: messages, endpoint: endpoint, apiKey: apiKey, useTools: false)
        return (result.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 非流式请求

    private func send(
        model: String,
        messages: [ChatMessage],
        endpoint: String,
        apiKey: String,
        useTools: Bool
    ) async throws -> ChatResult {
        guard let url = URL(string: "\(endpoint)/chat/completions") else {
            throw AIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // v2.2.0: 本地模型（Ollama）无 key 时省略 Authorization
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatRequest(
            model: model,
            messages: messages,
            tools: useTools ? encodeTools() : nil,
            tool_choice: useTools ? "auto" : nil,
            stream: nil,
            stream_options: nil
        )

        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)

        guard let httpResp = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResp.statusCode == 401 {
            throw AIError.unauthorized
        }
        if httpResp.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(httpResp.statusCode, body)
        }

        let result = try decoder.decode(ChatResponse.self, from: data)
        guard let choice = result.choices.first else {
            throw AIError.emptyResponse
        }
        return ChatResult(
            content: choice.message?.content,
            toolCalls: choice.message?.tool_calls,
            usage: result.usage,
            finishReason: choice.finish_reason,
            usedFallback: false
        )
    }

    // MARK: - 流式请求（SSE）

    private func streamSend(
        model: String,
        messages: [ChatMessage],
        endpoint: String,
        apiKey: String,
        useTools: Bool,
        onStream: @escaping (String) -> Void
    ) async throws -> ChatResult {
        guard let url = URL(string: "\(endpoint)/chat/completions") else {
            throw AIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatRequest(
            model: model,
            messages: messages,
            tools: useTools ? encodeTools() : nil,
            tool_choice: useTools ? "auto" : nil,
            stream: true,
            stream_options: ["include_usage": true]
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: req)
        guard let httpResp = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        if httpResp.statusCode == 401 {
            throw AIError.unauthorized
        }
        if httpResp.statusCode != 200 {
            throw AIError.httpError(httpResp.statusCode, "streaming request failed")
        }

        var content = ""
        var finishReason: String?
        var usage: Usage?
        // v2.4.9: 累积 SSE tool_calls 分片（OpenAI 协议：
        // 首个分片带 id/name，后续分片只有 function.arguments 增量）
        var toolCallAccumulator: [Int: (id: String, name: String, arguments: String)] = [:]

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            // 优先用 StreamChunkResponse 解码（Optional 字段兼容分片）；
            // 回退到 ChatResponse（兼容不含 tool_calls 的纯文本流）
            if let chunk = try? decoder.decode(StreamChunkResponse.self, from: data) {
                if let choice = chunk.choices?.first {
                    if let delta = choice.delta?.content {
                        content += delta
                        onStream(delta)
                    }
                    if let fragments = choice.delta?.tool_calls {
                        for frag in fragments {
                            guard let idx = frag.index else { continue }
                            var entry = toolCallAccumulator[idx] ?? (id: "", name: "", arguments: "")
                            if let id = frag.id { entry.id = id }
                            if let name = frag.function?.name { entry.name = name }
                            if let args = frag.function?.arguments { entry.arguments += args }
                            toolCallAccumulator[idx] = entry
                        }
                    }
                    if let reason = choice.finish_reason { finishReason = reason }
                }
                if let u = chunk.usage { usage = u }
            } else if let chunk = try? decoder.decode(ChatResponse.self, from: data) {
                if let delta = chunk.choices.first?.delta?.content {
                    content += delta
                    onStream(delta)
                }
                if let reason = chunk.choices.first?.finish_reason { finishReason = reason }
                if let u = chunk.usage { usage = u }
            }
        }

        // 组装累积的 tool_calls
        let assembledToolCalls: [ToolCall]? = toolCallAccumulator.isEmpty ? nil : toolCallAccumulator.keys.sorted().compactMap { idx in
            guard let entry = toolCallAccumulator[idx], !entry.id.isEmpty, !entry.name.isEmpty else { return nil }
            return ToolCall(id: entry.id, type: "function", function: FunctionCall(name: entry.name, arguments: entry.arguments))
        }

        return ChatResult(
            content: content.isEmpty ? nil : content,
            toolCalls: assembledToolCalls,
            usage: usage,
            finishReason: finishReason,
            usedFallback: false
        )
    }

    // MARK: - Private

    private func encodeTools() -> [[String: AnyCodable]] {
        AITools.definitions.compactMap { tool in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String,
                  let desc = fn["description"] as? String,
                  let params = fn["parameters"] as? [String: Any] else { return nil }
            return [
                "type": AnyCodable("function"),
                "function": AnyCodable([
                    "name": AnyCodable(name),
                    "description": AnyCodable(desc),
                    "parameters": AnyCodable(params)
                ])
            ]
        }
    }
}

// MARK: - AnyCodable

struct AnyCodable: Codable {
    let value: Any

    /// 递归包裹：把 [String: Any] / [Any] 也转换成可编码结构，
    /// 否则外层 AnyCodable 在 encode 时无法识别嵌套字典/数组，会落到 encodeNil()，
    /// 导致 AI 工具的 parameters 被序列化为 null。
    init(_ value: Any) {
        if let dict = value as? [String: Any] {
            var converted: [String: AnyCodable] = [:]
            for (k, v) in dict { converted[k] = AnyCodable(v) }
            self.value = converted
        } else if let array = value as? [Any] {
            self.value = array.map { AnyCodable($0) }
        } else if let anyCodable = value as? AnyCodable {
            self.value = anyCodable.value
        } else {
            self.value = value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? String { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? Bool { try container.encode(v) }
        else if let v = value as? [String: AnyCodable] { try container.encode(v) }
        else if let v = value as? [AnyCodable] { try container.encode(v) }
        else { try container.encodeNil() }
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "API Key 无效，请检查设置"
        case .httpError(let code, let body):
            return Localized("API 错误 %d: %@", code, String(body.prefix(200)))
        case .emptyResponse: return "AI 返回为空"
        case .invalidResponse: return "响应格式错误"
        }
    }
}
