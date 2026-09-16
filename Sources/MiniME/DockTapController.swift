import AppKit
import ApplicationServices
import CoreGraphics

/// 全局鼠标点击拦截器:
/// 监听 leftMouseDown → 判断是否点击在 Dock 图标上 →
/// 智能决定吞掉点击并最小化目标应用窗口,或放行给系统执行默认行为。
final class DockTapController: NSObject {
    static let shared = DockTapController()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dockBounds: CGRect = .null
    private var dockBoundsUpdatedAt: Date = .distantPast
    private(set) var isEnabled: Bool = false

    private override init() {
        super.init()
        // 屏幕参数变化(分辨率/Dock 位置改变)时刷新 Dock 区域缓存
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dockBoundsUpdatedAt = .distantPast
        }
    }

    // MARK: - 启停

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard eventTap == nil else { return }
        // 无辅助功能权限时无法创建事件 tap,由 AppDelegate 轮询授权后再启动
        guard Permissions.isTrusted else { return }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            DockTapController.handleTap(proxy: proxy, type: type, event: event, refcon: refcon)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // 允许修改/吞掉事件
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged<DockTapController>.passUnretained(self).toOpaque()
        ) else {
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - 事件回调

    private static func handleTap(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let controller = Unmanaged<DockTapController>.fromOpaque(refcon).takeUnretainedValue()

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系统超时禁用了 tap,重新启用
            if let tap = controller.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown:
            if controller.shouldInterceptClick(at: event.location) {
                return nil // 吞掉事件,Dock 不会激活应用
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - 拦截判断(智能模式)

    private func shouldInterceptClick(at point: CGPoint) -> Bool {
        guard isEnabled, Permissions.isTrusted else { return false }
        // 1. 廉价预过滤:点击是否落在 Dock 区域内
        guard dockFrameContains(point) else { return false }
        // 2. AX 命中测试:是否点在某个 Dock 图标上,拿到图标对应的应用名
        guard let itemTitle = dockItemTitle(at: point) else { return false }
        // 3. 应用是否在运行(未运行 → 放行,让系统正常启动)
        guard let runningApp = matchRunningApplication(named: itemTitle) else { return false }
        let pid = runningApp.processIdentifier
        // 4. 应用不在前台 → 放行点击,优先由系统把该应用的窗口切换到前台
        guard isFrontmost(pid: pid) else { return false }
        // 5. 是否有可见窗口(已全部最小化/无窗口 → 放行,让系统正常唤起)
        guard WindowMinimizer.hasVisibleWindows(pid: pid) else { return false }
        // 6. 应用已在前台且有可见窗口 → 吞掉点击,并异步执行最小化(避免阻塞事件回调)
        DispatchQueue.main.async {
            WindowMinimizer.minimizeWindows(pid: pid)
        }
        return true
    }

    /// 该应用当前是否为前台(最前)应用
    private func isFrontmost(pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    // MARK: - Dock 区域缓存

    private var dockPID: pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier
    }

    private func dockFrameContains(_ point: CGPoint) -> Bool {
        if dockBounds.isNull || Date().timeIntervalSince(dockBoundsUpdatedAt) > 2.0 {
            refreshDockBounds()
        }
        return dockBounds.contains(point)
    }

    private func refreshDockBounds() {
        dockBoundsUpdatedAt = Date()
        dockBounds = .null
        guard let pid = dockPID else { return }
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else {
            return
        }
        for window in list {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            dockBounds = dockBounds.union(rect)
        }
    }

    // MARK: - Dock 图标命中测试

    /// 返回被点击的 Dock 图标标题(通常是应用名),不是图标则返回 nil
    private func dockItemTitle(at point: CGPoint) -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &elementRef
        ) == .success, let element = elementRef else {
            return nil
        }
        // 沿 parent 链向上查找 role == AXDockItem 的元素
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let node = current else { return nil }
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                node, kAXRoleAttribute as CFString, &roleRef
            ) == .success, let role = roleRef as? String else {
                return nil
            }
            if role == "AXDockItem" {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    node, kAXTitleAttribute as CFString, &titleRef
                ) == .success,
                    let title = titleRef as? String, !title.isEmpty {
                    return title
                }
                return nil
            }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                node, kAXParentAttribute as CFString, &parentRef
            ) == .success,
                let parentAny = parentRef,
                CFGetTypeID(parentAny) == AXUIElementGetTypeID() else {
                return nil
            }
            current = unsafeBitCast(parentAny, to: AXUIElement.self)
        }
        return nil
    }

    // MARK: - 应用匹配

    private func matchRunningApplication(named title: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
                && $0.localizedName?.caseInsensitiveCompare(title) == .orderedSame
        }
    }
}
