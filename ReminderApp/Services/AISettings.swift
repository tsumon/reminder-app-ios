import Foundation

/// 用户自定义 AI API 配置（apiKey 存 Keychain，endpoint/model 存 UserDefaults）
final class AISettings: ObservableObject {
    static let shared = AISettings()

    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: key_endpoint) }
    }
    @Published var apiKey: String {
        // 存于 Keychain（与 WebDAV 密码一致），didSet 在 init 期间不触发，故 init 中显式写入
        didSet { KeychainHelper.save(apiKey, service: "reminder_ai", account: "apikey") }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: key_model) }
    }

    private let key_endpoint = "ai_endpoint"
    private let key_apikey   = "ai_apikey"
    private let key_model    = "ai_model"

    /// 是否已配置（有 API Key 才能对话）
    var isConfigured: Bool {
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        self.apiEndpoint = UserDefaults.standard.string(forKey: key_endpoint) ?? "https://api.openai.com/v1"
        // AI key：优先从 Keychain 读取；兼容旧版明文 UserDefaults（首次启动自动迁移并清除明文）
        if let stored = KeychainHelper.read(service: "reminder_ai", account: "apikey"), !stored.isEmpty {
            self.apiKey = stored
        } else if let legacy = UserDefaults.standard.string(forKey: key_apikey), !legacy.isEmpty {
            self.apiKey = legacy
            KeychainHelper.save(legacy, service: "reminder_ai", account: "apikey")
            UserDefaults.standard.removeObject(forKey: key_apikey)
        } else {
            self.apiKey = ""
        }
        self.model       = UserDefaults.standard.string(forKey: key_model)    ?? "gpt-4o-mini"
    }
}
