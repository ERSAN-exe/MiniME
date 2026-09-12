import AppKit
import ApplicationServices

enum Permissions {
    /// 是否已获得辅助功能权限
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权提示(引导用户到 系统设置 → 隐私与安全性 → 辅助功能)
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 打开系统设置的辅助功能面板
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
