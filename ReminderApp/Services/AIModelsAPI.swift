import Foundation

/// OpenAI 兼容模型列表：URL 拼接、`data[].id` 解析、原始 HTTP 错误摘要。
enum AIModelsAPI {
    /// `{base}/models`；去掉尾斜杠。base 已是 `.../v1` 时得到 `.../v1/models`，不另拼 `/v1`。
    static func modelsURL(from base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        return URL(string: s + "/models")
    }

    static func parseModelIDs(from data: Data) throws -> [String] {
        struct Envelope: Decodable {
            struct Item: Decodable { let id: String? }
            let data: [Item]?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        var seen = Set<String>()
        var ids: [String] = []
        for item in env.data ?? [] {
            let id = (item.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            ids.append(id)
        }
        return ids
    }

    /// 原始 HTTP 状态 + body 摘要（CPA / 兼容端点 401/404 排查）。
    static func formatHTTPError(status: Int, body: Data) -> String {
        formatHTTPError(status: status, body: String(data: body, encoding: .utf8) ?? "")
    }

    static func formatHTTPError(status: Int, body: String) -> String {
        let summary = summarizeBody(body)
        return summary.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(summary)"
    }

    static func summarizeBody(_ body: String, limit: Int = 240) -> String {
        let collapsed = body
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit))
    }

    /// 主/备用上次选中的 model id（与当前输入框分开记，未点保存也保留）。
    enum LastSelected {
        static let primaryKey = "ai_last_selected_model"
        static let fallbackKey = "ai_last_selected_fallback_model"

        static func save(_ id: String, isFallback: Bool) {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            UserDefaults.standard.set(trimmed, forKey: isFallback ? fallbackKey : primaryKey)
        }

        static func load(isFallback: Bool) -> String? {
            let v = UserDefaults.standard.string(forKey: isFallback ? fallbackKey : primaryKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (v?.isEmpty == false) ? v : nil
        }

        /// 上次选中的排最前，其余保持接口返回顺序。
        static func ordered(_ ids: [String], isFallback: Bool) -> [String] {
            guard let last = load(isFallback: isFallback), ids.contains(last) else { return ids }
            return [last] + ids.filter { $0 != last }
        }
    }
}
