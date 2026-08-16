import Foundation

// v2.4.6: 从 AIChatView.swift 提取（模型与 View 解耦，可被 macOS 回归工具直接编译验证）

/// v2.4.2: AI 对话历史持久化（UserDefaults JSON，保留最近 200 条）
enum ChatHistoryStore {
    private static let key = "ai_chat_history"
    private static let maxCount = 200

    struct Entry: Codable {
        var role: String
        var content: String
        var time: Date
    }

    static func save(_ messages: [ChatMessage]) {
        let entries = messages.filter { !$0.content.isEmpty }.suffix(maxCount).map {
            Entry(role: roleKey($0.role), content: $0.content, time: $0.timestamp)
        }
        if let data = try? JSONEncoder().encode(Array(entries)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.map {
            ChatMessage(role: roleFrom($0.role), content: $0.content, timestamp: $0.time)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func roleKey(_ r: ChatMessage.MessageRole) -> String {
        switch r {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        case .tool: return "tool"
        }
    }

    private static func roleFrom(_ k: String) -> ChatMessage.MessageRole {
        switch k {
        case "user": return .user
        case "assistant": return .assistant
        case "system": return .system
        default: return .tool
        }
    }
}

/// v2.2.0: AI 工具调用步骤（Agent 可视化：执行中 → 完成/失败）
struct ToolStep: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let status: String      // running / done / error
    let summary: String?
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    var content: String
    let timestamp: Date
    var toolSteps: [ToolStep] = []

    enum MessageRole: Equatable {
        case user, assistant, system, tool
    }
}
