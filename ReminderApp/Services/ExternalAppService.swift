import Foundation

/// AI 服务商信息 — 仅用于「免费获取 API Key」指引（免 API 网页跳转模式已移除）
struct ExternalAppService {

    enum Provider: String, CaseIterable, Identifiable {
        case deepseek
        case qwen
        case doubao

        var id: String { rawValue }

        var name: String {
            switch self {
            case .deepseek: return "DeepSeek"
            case .qwen:     return "通义千问"
            case .doubao:   return "豆包"
            }
        }

        /// 免费 API Key 获取地址
        var apiKeyURL: URL {
            switch self {
            case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")!
            case .qwen:     return URL(string: "https://dashscope.console.aliyun.com/apiKey")!
            case .doubao:   return URL(string: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey")!
            }
        }

        /// 免费额度说明
        var freeTierInfo: String {
            switch self {
            case .deepseek: return "注册即送 500 万 tokens（约数月免费使用）"
            case .qwen:     return "开通即送 100 万 tokens（qwen-turbo 免费）"
            case .doubao:   return "注册即送 50 万 tokens 免费额度"
            }
        }
    }
}
