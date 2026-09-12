import AppKit

// MiniME:点击 Dock 图标最小化应用窗口(智能模式)
// - 应用有可见窗口 → 吞掉点击,不激活应用,将其所有窗口最小化
// - 应用未运行 / 窗口已全部最小化或无窗口 → 放行点击,系统执行默认行为
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 菜单栏应用,不占 Dock 位
app.run()
