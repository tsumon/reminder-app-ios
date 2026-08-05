import Foundation

/// 用户自定义 AI API 配置（存 UserDefaults）
final class AISettings: ObservableObject {
    static let shared = AISettings()

    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: key_endpoint) }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: key_apikey) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: key_model) }
    }

    /// 免 API 模式：不填 Key，直接跳转外部 App 网页版
    @Published var useNoAPIMode: Bool {
        didSet { UserDefaults.standard.set(useNoAPIMode, forKey: key_noapi) }
    }

    /// 免 API 模式下默认跳转哪个服务
    @Published var noAPIProvider: String {
        didSet { UserDefaults.standard.set(noAPIProvider, forKey: key_noapi_provider) }
    }

    private let key_endpoint      = "ai_endpoint"
    private let key_apikey        = "ai_apikey"
    private let key_model         = "ai_model"
    private let key_noapi         = "ai_noapi"
    private let key_noapi_provider = "ai_noapi_provider"

    /// 是否已配置（有 API Key 或开启免 API 模式）
    var isConfigured: Bool {
        if useNoAPIMode { return true }
        return !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        self.apiEndpoint    = UserDefaults.standard.string(forKey: key_endpoint) ?? "https://api.openai.com/v1"
        self.apiKey         = UserDefaults.standard.string(forKey: key_apikey)   ?? ""
        self.model          = UserDefaults.standard.string(forKey: key_model)    ?? "gpt-4o-mini"
        self.useNoAPIMode   = UserDefaults.standard.bool(forKey: key_noapi)
        self.noAPIProvider  = UserDefaults.standard.string(forKey: key_noapi_provider) ?? "deepseek"
    }
}
