import AppKit

/// 菜单栏图标:程序化绘制的「窗口 + 标题栏 + 底部最小化条」线条轮廓
/// 以 template image 输出,自动适配菜单栏深浅色(深色模式显示为白色线条)
enum MenuBarIcon {
    /// - Parameter size: 图标点数(菜单栏推荐 18pt)
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.set()

            let lineWidth = max(1.2, size * 0.095)
            let inset = lineWidth / 2 + size * 0.045
            let windowRect = rect.insetBy(dx: inset, dy: inset)
            let radius = windowRect.width * 0.24

            // 1. 窗口外框(圆角矩形轮廓)
            let outline = NSBezierPath(roundedRect: windowRect,
                                       xRadius: radius, yRadius: radius)
            outline.lineWidth = lineWidth
            outline.stroke()

            // 2. 标题栏分割线(靠近顶部,横贯整个窗口宽度)
            let titleY = windowRect.maxY - windowRect.height * 0.28
            let titleLine = NSBezierPath()
            titleLine.move(to: NSPoint(x: windowRect.minX, y: titleY))
            titleLine.line(to: NSPoint(x: windowRect.maxX, y: titleY))
            titleLine.lineWidth = lineWidth
            titleLine.stroke()

            // 3. 底部最小化条(实心圆角条,居中)
            let barHeight = size * 0.155
            let barWidth = windowRect.width * 0.60
            let barRect = NSRect(x: windowRect.midX - barWidth / 2,
                                 y: windowRect.minY + windowRect.height * 0.15,
                                 width: barWidth,
                                 height: barHeight)
            NSBezierPath(roundedRect: barRect,
                         xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
