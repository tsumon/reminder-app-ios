import Foundation

/// 用户自定义 AI API 配置（apiKey 存 Keychain，其余存 UserDefaults）
/// v2.2.0：多 provider——主配置 + 备用配置（自动降级）+ 本地模型（Ollama 免 key）
final class AISettings: ObservableObject {
    static let shared = AISettings()

    // ── 主配置 ──

    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: key_endpoint) }
    }
    @Published var apiKey: String {
        didSet { KeychainHelper.save(apiKey, service: "reminder_ai", account: "apikey") }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: key_model) }
    }

    // ── 本地模型（v2.2.0：如 Ollama，apiKey 可空）──

    @Published var isLocal: Bool {
        didSet { UserDefaults.standard.set(isLocal, forKey: key_isLocal) }
    }

    // ── 备用配置（v2.2.0：主配置失败自动降级）──

    @Published var fallbackEnabled: Bool {
        didSet { UserDefaults.standard.set(fallbackEnabled, forKey: key_fallbackEnabled) }
    }
    @Published var fallbackEndpoint: String {
        didSet { UserDefaults.standard.set(fallbackEndpoint, forKey: key_fallbackEndpoint) }
    }
    @Published var fallbackKey: String {
        didSet { KeychainHelper.save(fallbackKey, service: "reminder_ai", account: "fallback_key") }
    }
    @Published var fallbackModel: String {
        didSet { UserDefaults.standard.set(fallbackModel, forKey: key_fallbackModel) }
    }

    private let key_endpoint = "ai_endpoint"
    private let key_apikey   = "ai_apikey"
    private let key_model    = "ai_model"
    private let key_isLocal  = "ai_is_local"
    private let key_fallbackEnabled  = "ai_fallback_enabled"
    private let key_fallbackEndpoint = "ai_fallback_endpoint"
    private let key_fallbackModel    = "ai_fallback_model"

    /// 主配置是否可用（本地模型无需 key）
    var isConfigured: Bool {
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isLocal || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// 备用配置是否可用
    var hasFallback: Bool {
        fallbackEnabled &&
        !fallbackEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !fallbackKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        self.isLocal     = UserDefaults.standard.bool(forKey: key_isLocal)

        self.fallbackEnabled  = UserDefaults.standard.bool(forKey: key_fallbackEnabled)
        self.fallbackEndpoint = UserDefaults.standard.string(forKey: key_fallbackEndpoint) ?? "https://api.deepseek.com/v1"
        self.fallbackModel    = UserDefaults.standard.string(forKey: key_fallbackModel)    ?? "deepseek-chat"
        // 备用 key：Keychain 读取（无旧明文迁移，全新字段）
        self.fallbackKey = KeychainHelper.read(service: "reminder_ai", account: "fallback_key") ?? ""
    }
}
