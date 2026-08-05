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

    private let key_endpoint = "ai_endpoint"
    private let key_apikey   = "ai_apikey"
    private let key_model    = "ai_model"

    /// 是否已配置
    var isConfigured: Bool {
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        self.apiEndpoint = UserDefaults.standard.string(forKey: key_endpoint) ?? "https://api.openai.com/v1"
        self.apiKey      = UserDefaults.standard.string(forKey: key_apikey)   ?? ""
        self.model       = UserDefaults.standard.string(forKey: key_model)    ?? "gpt-4o-mini"
    }
}
