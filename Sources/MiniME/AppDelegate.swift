import AppKit
import ServiceManagement

/// 菜单栏常驻 UI:状态图标 + 精简菜单(开机自启 / 关于 / 退出)+ 原生风格关于窗口
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let controller = DockTapController.shared
    private var pollTimer: Timer?
    private var wasTrusted = false
    private var aboutWindow: NSWindow?
    private var changelogWindow: NSWindow?
    private var lastMenuSignature = ""

    /// 项目主页
    private static let projectURL = URL(string: "https://github.com/ERSAN-exe/MiniME")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // 始终启用拦截;无辅助功能权限时通过轮询在授权后自动生效
        controller.setEnabled(true)
        wasTrusted = Permissions.isTrusted
        if !wasTrusted {
            Permissions.request()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    // MARK: - 状态栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // 自绘线条轮廓图标(template image,自动适配深浅色菜单栏)
            let icon = MenuBarIcon.make(size: 18)
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
            button.toolTip = "MiniME"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func refreshState() {
        let trusted = Permissions.isTrusted
        if trusted != wasTrusted {
            wasTrusted = trusted
            if trusted {
                controller.setEnabled(true) // 授权后重试创建事件 tap
            }
        }
        updateMenuIfNeeded()
    }

    // MARK: - 菜单(仅保留:开机自启 / 关于 / 退出)

    private func updateMenuIfNeeded() {
        let signature = menuSignature()
        guard signature != lastMenuSignature else { return }
        lastMenuSignature = signature
        statusItem?.menu = buildMenu()
    }

    private func menuSignature() -> String {
        let loginEnabled: Bool
        if #available(macOS 13.0, *) {
            loginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            loginEnabled = false
        }
        return "\(Permissions.isTrusted)-\(loginEnabled)"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let login = NSMenuItem(title: L10n.t("menu.launchAtLogin", "Launch at Login"),
                               action: #selector(toggleLoginItem),
                               keyEquivalent: "l")
        login.target = self
        if #available(macOS 13.0, *) {
            login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        } else {
            login.isEnabled = false
        }
        menu.addItem(login)

        let about = NSMenuItem(title: L10n.t("menu.about", "About MiniME"),
                               action: #selector(showAbout),
                               keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: L10n.t("menu.quit", "Quit MiniME"),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    // MARK: - 关于窗口(macOS 原生 About 风格)

    @objc private func showAbout() {
        if let window = aboutWindow {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = makeAboutWindow()
        aboutWindow = window
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeAboutWindow() -> NSWindow {
        let contentSize = NSSize(width: 400, height: 366)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = L10n.t("about.windowTitle", "About MiniME")
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true

        // 毛玻璃背景
        let visual = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        visual.material = .underWindowBackground
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.autoresizingMask = [.width, .height]

        // 应用图标:重绘为指定点数,避免沿用原图(1024pt)的固有尺寸
        let iconSide: CGFloat = 128
        let iconView = NSImageView()
        iconView.image = appIcon(side: iconSide)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentHuggingPriority(.required, for: .vertical)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: iconSide),
            iconView.heightAnchor.constraint(equalToConstant: iconSide),
        ])

        let nameField = aboutLabel("MiniME",
                                   font: .boldSystemFont(ofSize: 26),
                                   color: .labelColor)
        let versionField = aboutLabel(versionString(),
                                      font: .systemFont(ofSize: 13),
                                      color: .secondaryLabelColor)
        let taglineField = aboutLabel(L10n.t("about.tagline",
                                             "Click a Dock icon to minimize that app's windows"),
                                      font: .systemFont(ofSize: 13),
                                      color: .secondaryLabelColor)
        // 按钮行:项目地址 + 查看日志(并排)
        let linkButton = makeProjectLinkButton()
        let changelogButton = makeChangelogButton()
        let buttonRow = NSStackView(views: [linkButton, changelogButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 16

        // 作者名不参与本地化,中英文版本保持一致
        let copyrightField = aboutLabel("铃一贰叁 制作",
                                        font: .systemFont(ofSize: 11),
                                        color: .tertiaryLabelColor)

        let stack = NSStackView(views: [iconView, nameField, versionField,
                                        taglineField, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(18, after: iconView)
        stack.setCustomSpacing(12, after: taglineField)
        stack.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(stack)

        copyrightField.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(copyrightField)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: visual.centerXAnchor),
            stack.topAnchor.constraint(equalTo: visual.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: visual.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: visual.trailingAnchor, constant: -20),
            copyrightField.centerXAnchor.constraint(equalTo: visual.centerXAnchor),
            copyrightField.bottomAnchor.constraint(equalTo: visual.bottomAnchor, constant: -16),
        ])

        window.contentView = visual
        return window
    }

    private func aboutLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.lineBreakMode = .byClipping
        return field
    }

    /// 关于页面的「项目地址」链接按钮(无边框、链接色、悬停手型光标)
    private func makeProjectLinkButton() -> NSButton {
        makeLinkButton(title: L10n.t("about.projectLink", "Project Page"),
                       symbolName: "link",
                       action: #selector(openProjectURL),
                       toolTip: Self.projectURL.absoluteString)
    }

    /// 关于页面的「查看日志」按钮
    private func makeChangelogButton() -> NSButton {
        makeLinkButton(title: L10n.t("about.changelogButton", "View Changelog"),
                       symbolName: "doc.text",
                       action: #selector(showChangelog),
                       toolTip: L10n.t("changelog.windowTitle", "Changelog"))
    }

    /// 通用链接样式按钮(无边框、链接色、悬停手型光标)
    private func makeLinkButton(title: String,
                                symbolName: String,
                                action: Selector,
                                toolTip: String) -> NSButton {
        let button = LinkButton(title: title, target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .inline
        button.focusRingType = .none
        if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            button.image = icon
            button.imagePosition = .imageLeading
            button.contentTintColor = .linkColor
        }
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.linkColor,
            ]
        )
        button.toolTip = toolTip
        return button
    }

    /// 按指定点数重绘应用图标,确保固有尺寸正确且缩放清晰
    private func appIcon(side: CGFloat) -> NSImage {
        let source: NSImage
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            source = image
        } else {
            source = NSApp.applicationIconImage
        }
        let target = NSSize(width: side, height: side)
        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: target),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    private func versionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return L10n.format("about.versionFormat", "Version %@ (build %@)", version, build)
    }

    // MARK: - 动作

    @objc private func openProjectURL() {
        NSWorkspace.shared.open(Self.projectURL)
    }

    /// 弹出更新日志窗口(按当前界面语言加载对应语言的日志文件)
    @objc private func showChangelog() {
        if let window = changelogWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = makeChangelogWindow(text: loadChangelogText())
        changelogWindow = window
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeChangelogWindow(text: String) -> NSWindow {
        let contentSize = NSSize(width: 480, height: 340)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L10n.t("changelog.windowTitle", "Changelog")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 160)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: contentSize))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        window.contentView = content
        return window
    }

    /// 读取 App 包内与当前界面语言对应的日志文件(仅使用精简版 `*.txt`)
    private func loadChangelogText() -> String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let baseName = language.hasPrefix("zh") ? "changelogzh" : "changelogen"
        if let url = Bundle.main.url(forResource: baseName, withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return L10n.t("changelog.unavailable", "Changelog file not found.")
    }

    @objc private func toggleLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("alert.loginItem.title", "Failed to Enable Launch at Login")
            alert.informativeText = L10n.format(
                "alert.loginItem.message",
                "Please make sure MiniME.app is located in the Applications folder and is not blocked by the system.\n\n%@",
                error.localizedDescription
            )
            alert.runModal()
        }
        updateMenuIfNeeded()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === aboutWindow {
            aboutWindow = nil
        }
        if (notification.object as? NSWindow) === changelogWindow {
            changelogWindow = nil
        }
    }
}

/// 链接样式按钮:鼠标悬停时显示手型光标
private final class LinkButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
