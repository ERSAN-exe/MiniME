import Foundation

/// 轻量本地化:
/// - 文案存放在 App 包内的 `en.lproj` / `zh-Hans.lproj` → `Localizable.strings`
/// - 系统按「语言与地区」偏好自动选择;找不到时回退到传入的英语原文
enum L10n {
    /// 取本地化文案,缺失时返回 fallback(英语原文)
    static func t(_ key: String, _ fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    /// 带格式化参数的本地化文案
    static func format(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
        String(format: t(key, fallback), arguments: args)
    }
}
