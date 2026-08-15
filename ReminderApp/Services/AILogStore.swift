import Foundation

/// v2.2.0: AI 调用日志——记录最近 20 次对话（模型/provider/轮数/token/耗时/成败），
/// 供诊断页查看（AI 可观测性）。UserDefaults 持久化，重启不丢。
enum AILogStore {

    struct Entry: Codable, Identifiable {
        var id = UUID()
        var time: Date = Date()
        var model: String = ""
        var provider: String = ""      // primary / fallback
        var turns: Int = 0             // Agent 工具轮数
        var promptTokens: Int?
        var completionTokens: Int?
        var durationMs: Int = 0
        var ok: Bool = true
        var error: String?
    }

    private static let key = "ai_log_entries"
    private static let maxCount = 20

    static func add(_ entry: Entry) {
        var list = recent()
        list.insert(entry, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func recent() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return list
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
