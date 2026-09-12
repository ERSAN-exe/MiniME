#!/usr/bin/env swift
// MiniME 应用图标生成脚本
// 设计:白底 + 黑色边框圆角图标,左上角 macOS 红绿灯按钮,中央「MiniME!」文字
// 输出:build/AppIcon.iconset/(全套尺寸,供 iconutil 转换为 icns)
import AppKit

let outputDir = URL(fileURLWithPath: "build/AppIcon.iconset")

/// 在给定尺寸的画布上绘制图标(CG 坐标系,原点左下)
func drawIcon(context ctx: CGContext, size: CGFloat) {
    // macOS 图标栅格:圆角矩形内容区占画布约 80.5%,居中
    let inset = size * 0.0975
    let content = CGRect(x: inset, y: inset,
                         width: size - inset * 2, height: size - inset * 2)
    let radius = content.width * 0.2237
    let path = CGPath(roundedRect: content,
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    let u = size / 1024.0

    // 1. 白色底(裁剪到圆角矩形)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(content)

    // 2. 左上角 macOS 红绿灯按钮(红 / 黄 / 绿),黄色按钮上带最小化横线「−」
    let dotDiameter: CGFloat = 76 * u
    let dotSpacing: CGFloat = 104 * u
    let dotMargin: CGFloat = 66 * u
    let dotCenterY = content.maxY - dotMargin - dotDiameter / 2
    let lightColors: [(CGFloat, CGFloat, CGFloat)] = [
        (1.000, 0.373, 0.341), // 红
        (0.996, 0.737, 0.180), // 黄
        (0.157, 0.784, 0.251), // 绿
    ]
    for (index, rgb) in lightColors.enumerated() {
        let cx = content.minX + dotMargin + dotDiameter / 2 + CGFloat(index) * dotSpacing
        let rect = CGRect(x: cx - dotDiameter / 2, y: dotCenterY - dotDiameter / 2,
                          width: dotDiameter, height: dotDiameter)
        ctx.beginPath()
        ctx.addEllipse(in: rect)
        ctx.setFillColor(CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
        ctx.fillPath()
        // 黄色按钮:绘制 macOS 最小化符号(深黄色横线「−」)
        if index == 1 {
            let lineWidth = dotDiameter * 0.17
            let lineLength = dotDiameter * 0.58
            let lineRect = CGRect(x: cx - lineLength / 2,
                                  y: dotCenterY - lineWidth / 2,
                                  width: lineLength, height: lineWidth)
            ctx.addPath(CGPath(roundedRect: lineRect,
                               cornerWidth: lineWidth / 2, cornerHeight: lineWidth / 2,
                               transform: nil))
            ctx.setFillColor(CGColor(red: 0.874, green: 0.571, blue: 0.050, alpha: 1))
            ctx.fillPath()
        }
    }

    // 3. 中央「MiniME!」文字(黑色粗体,宽度自适应)
    drawCenteredText(content: content)

    ctx.restoreGState() // 移除裁剪

    // 4. 黑色边框
    ctx.setLineWidth(30 * u)
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.addPath(path)
    ctx.strokePath()
}

/// 在内容区垂直居中绘制「MiniME!」(利用当前 NSGraphicsContext)
func drawCenteredText(content: CGRect) {
    let text = "MiniME!" as NSString
    let fontSize = content.width * 0.21
    var attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.black,
    ]
    var textSize = text.size(withAttributes: attrs)
    // 过宽时按比例缩小,保证留白
    let maxWidth = content.width * 0.80
    if textSize.width > maxWidth {
        let scale = maxWidth / textSize.width
        attrs[.font] = NSFont.systemFont(ofSize: fontSize * scale, weight: .bold)
        textSize = text.size(withAttributes: attrs)
    }
    // 稍微下移,平衡顶部红绿灯的视觉重量
    let origin = CGPoint(x: content.midX - textSize.width / 2,
                         y: content.midY - textSize.height / 2 - content.height * 0.02)
    text.draw(at: origin, withAttributes: attrs)
}

/// 以指定像素尺寸渲染 PNG 数据
func renderPNG(pixelSize: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        throw NSError(domain: "MiniME.IconGen", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "无法创建位图"])
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let nsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "MiniME.IconGen", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "无法创建图形上下文"])
    }
    NSGraphicsContext.current = nsContext
    drawIcon(context: nsContext.cgContext, size: CGFloat(pixelSize))
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MiniME.IconGen", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "PNG 编码失败"])
    }
    return data
}

// MARK: - 主流程

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    let data = try renderPNG(pixelSize: px)
    try data.write(to: outputDir.appendingPathComponent(name))
    print("生成 \(name) (\(px)x\(px))")
}
print("iconset 完成:\(outputDir.path)")
