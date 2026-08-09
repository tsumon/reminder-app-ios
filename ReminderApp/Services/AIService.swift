import Foundation

/// OpenAI 兼容 API 调用服务
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

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let tools: [[String: AnyCodable]]?
        let tool_choice: String?

        enum CodingKeys: String, CodingKey {
            case model, messages, tools
            case tool_choice
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(model, forKey: .model)
            try c.encode(messages, forKey: .messages)
            if let t = tools { try c.encode(t, forKey: .tools) }
            if let tc = tool_choice { try c.encode(tc, forKey: .tool_choice) }
        }
    }

    struct ChatResponse: Codable {
        let choices: [Choice]
    }

    struct Choice: Codable {
        let message: ChatMessage
        let finish_reason: String?
    }

    // MARK: - Public

    func chat(
        model: String,
        messages: [ChatMessage],
        endpoint: String,
        apiKey: String
    ) async throws -> ChatMessage {
        // endpoint 来自用户设置自由输入，可能含空格/中文/无 host，强制解包会崩溃
        guard let url = URL(string: "\(endpoint)/chat/completions") else {
            throw AIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(
            model: model,
            messages: messages,
            tools: encodeTools(),
            tool_choice: "auto"
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
        return choice.message
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
