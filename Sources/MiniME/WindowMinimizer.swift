import AppKit
import ApplicationServices
import CoreGraphics

/// 通过 Accessibility API 查询并最小化目标应用的窗口
enum WindowMinimizer {
    /// 判断指定应用当前是否有可见的普通窗口(位于第 0 层、非零尺寸、当前在屏幕上)
    static func hasVisibleWindows(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        for window in list {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid else { continue }
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0 else { continue }
            if let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               rect.width < 1 || rect.height < 1 {
                continue
            }
            return true
        }
        return false
    }

    /// 将应用所有未最小化的窗口最小化(等价于点击黄色最小化按钮)
    static func minimizeWindows(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement] else {
            return
        }
        for window in windows {
            var minimizedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window, kAXMinimizedAttribute as CFString, &minimizedRef
            ) == .success,
                let minimized = minimizedRef as? Bool,
                !minimized else {
                continue
            }
            AXUIElementSetAttributeValue(
                window, kAXMinimizedAttribute as CFString, kCFBooleanTrue
            )
        }
    }
}
