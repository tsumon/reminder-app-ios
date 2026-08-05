import UIKit
import SafariServices

/// 免 API 模式 — 跳转外部 AI 服务（网页版）
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

        var icon: String {
            switch self {
            case .deepseek: return "d.square.fill"
            case .qwen:     return "q.square.fill"
            case .doubao:   return "b.square.fill"
            }
        }

        var color: String {
            switch self {
            case .deepseek: return "#4D6BFE"
            case .qwen:     return "#615CED"
            case .doubao:   return "#00D4AA"
            }
        }

        /// 网页版地址
        var webURL: URL {
            switch self {
            case .deepseek: return URL(string: "https://chat.deepseek.com/")!
            case .qwen:     return URL(string: "https://tongyi.aliyun.com/qianwen/")!
            case .doubao:   return URL(string: "https://www.doubao.com/chat/")!
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

        /// API 预设
        var apiEndpoint: String {
            switch self {
            case .deepseek: return "https://api.deepseek.com/v1"
            case .qwen:     return "https://dashscope.aliyuncs.com/compatible-mode/v1"
            case .doubao:   return "https://ark.cn-beijing.volces.com/api/v3"
            }
        }

        var apiModel: String {
            switch self {
            case .deepseek: return "deepseek-chat"
            case .qwen:     return "qwen-plus"
            case .doubao:   return "doubao-lite-32k"
            }
        }
    }

    /// 复制文字到剪贴板并打开网页版
    static func openWeb(for provider: Provider, withText text: String) {
        UIPasteboard.general.string = text

        // 顶部弹窗提示
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let vc = window.rootViewController {
            showToast(on: vc, message: "已复制到剪贴板，请在「\(provider.name)」网页中粘贴发送")
        }

        UIApplication.shared.open(provider.webURL)
    }

    /// 打开 Safari ViewController（应用内浏览器）
    static func openInAppBrowser(for provider: Provider, from viewController: UIViewController) {
        let safariVC = SFSafariViewController(url: provider.webURL)
        viewController.present(safariVC, animated: true)
    }

    private static func showToast(on vc: UIViewController, message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        vc.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            alert.dismiss(animated: true)
        }
    }
}
