import Foundation

/// 手动语言切换（v2.0.4）
/// 偏好存 UserDefaults（key: appLanguage）：system/zh-Hans/en/zh-Hant/ja/ko
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"
    case zhHant = "zh-Hant"
    case ja = "ja"
    case ko = "ko"

    var id: String { rawValue }

    /// 语言选项显示名：语言名用各自语言自称（不参与本地化）；「跟随系统」随当前语言翻译
    var displayName: String {
        switch self {
        case .system: return "跟随系统".localized
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }
}

enum AppLanguageManager {
    static let key = "appLanguage"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "system") ?? .system
    }

    /// 生效的本地化 bundle：跟随系统时用主 bundle（NSLocalizedString 按系统语言挑选）；
    /// 手动指定时查对应 lproj（由 Localizable.xcstrings 编译生成），缺失回退主 bundle。
    static var bundle: Bundle {
        let lang = current
        guard lang != .system else { return .main }
        if let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .main
    }
}

/// 多语言本地化工具。
/// 设计：以「简体中文」文本作为 key（source language = zh-Hans），
/// 在 Localizable.xcstrings 中查找对应翻译；未提供翻译的语言自动回退到中文。
///
/// 用法：
///   Text("提醒".localized)                 // 普通文案
///   Text(Localized("下次：%@", text))       // 带参数（key 中用 %@ / %d 占位）
extension String {
    var localized: String {
        NSLocalizedString(self, tableName: "Localizable", bundle: AppLanguageManager.bundle, comment: "")
    }
}

/// 带参数的本地化。key 中使用 %@ / %d 占位符（与 String(format:) 一致）。
func Localized(_ format: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(format, tableName: "Localizable", bundle: AppLanguageManager.bundle, comment: ""), arguments: args)
}
