import Foundation

/// 多语言本地化工具。
/// 设计：以「简体中文」文本作为 key（source language = zh-Hans），
/// 在 Localizable.xcstrings 中查找对应翻译；未提供翻译的语言自动回退到中文。
///
/// 用法：
///   Text("提醒".localized)                 // 普通文案
///   Text(Localized("下次：%@", text))       // 带参数（key 中用 %@ / %d 占位）
extension String {
    var localized: String {
        NSLocalizedString(self, tableName: "Localizable", bundle: .main, comment: "")
    }
}

/// 带参数的本地化。key 中使用 %@ / %d 占位符（与 String(format:) 一致）。
func Localized(_ format: String, _ args: CVarArg...) -> String {
    String(format: format.localized, arguments: args)
}
