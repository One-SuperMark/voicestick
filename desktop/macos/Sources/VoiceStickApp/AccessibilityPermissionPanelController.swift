import AppKit
import ApplicationServices

/// A drag source attached visually to System Settings without taking its focus.
/// Adding the app and enabling the permission remain user actions in macOS.
final class AccessibilityPermissionPanelController: NSWindowController, NSWindowDelegate {
    private let instruction = NSTextField(wrappingLabelWithString: "")
    private let permissionStatus = NSTextField(labelWithString: "")
    private var trackingTimer: Timer?
    private var presentationID: UUID?
    private var isDraggingApp = false
    private var didActivateSettings = false
    private var settingsOpenFailed = false
    private var measuredSettingsFrame: NSRect?
    private var settingsSidebarWidth: CGFloat = 232
    private var preferredPanelHeight: CGFloat { permissionStatus.isHidden ? 124 : 150 }

    init(appURL: URL = Bundle.main.bundleURL) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "VoiceStick 辅助功能授权引导"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init(window: panel)
        panel.delegate = self

        let content = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        content.material = .popover
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = true
        panel.contentView = content

        let arrow = NSImageView(image: NSImage(
            systemSymbolName: "arrow.up", accessibilityDescription: "拖到上方权限列表"
        ) ?? NSImage())
        arrow.contentTintColor = .controlAccentColor
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 27, weight: .bold)
        instruction.font = .systemFont(ofSize: 14, weight: .medium)
        instruction.maximumNumberOfLines = 2
        instruction.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭授权引导") ?? NSImage(),
            target: self, action: #selector(dismissGuide)
        )
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "关闭授权引导"
        closeButton.setAccessibilityLabel("关闭授权引导")
        let heading = NSStackView(views: [arrow, instruction, closeButton])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 16
        // The card icon is inset 12 pt and 36 pt wide; center the 28 pt arrow
        // on that same column, then align the instruction with the app name.
        heading.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)

        let appRow = DraggableApplicationView(appURL: appURL)
        appRow.onDraggingChanged = { [weak self] in self?.isDraggingApp = $0 }
        permissionStatus.font = .systemFont(ofSize: 11)
        permissionStatus.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, appRow, permissionStatus])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            heading.heightAnchor.constraint(equalToConstant: 32),
            arrow.widthAnchor.constraint(equalToConstant: 28),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            appRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            appRow.heightAnchor.constraint(equalToConstant: 54)
        ])
        updatePermissionStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { trackingTimer?.invalidate() }

    func show() {
        let id = UUID()
        presentationID = id
        didActivateSettings = false
        settingsOpenFailed = false
        measuredSettingsFrame = nil
        settingsSidebarWidth = 232
        updatePermissionStatus()
        positionPanel(settingsPID: nil)
        window?.orderFrontRegardless()
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.trackSystemSettings()
        }
        trackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        let workspace = NSWorkspace.shared
        guard let settingsURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            openPermissionPane()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: settingsURL, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self, self.presentationID == id else { return }
                self.openPermissionPane()
                if error == nil {
                    app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
                self.trackSystemSettings()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        presentationID = nil
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    @objc private func dismissGuide() { close() }

    private func openPermissionPane() {
        for text in [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ] {
            if let url = URL(string: text), NSWorkspace.shared.open(url) { return }
        }
        settingsOpenFailed = true
        updatePermissionStatus()
    }

    private func updatePermissionStatus() {
        let isTrusted = AXIsProcessTrusted()
        instruction.stringValue = isTrusted
            ? "VoiceStick 已获辅助功能权限"
            : "将 VoiceStick 拖到上方列表，允许辅助功能访问"
        permissionStatus.isHidden = isTrusted && !settingsOpenFailed
        permissionStatus.stringValue = settingsOpenFailed
            ? "请打开系统设置 → 隐私与安全性 → 辅助功能。"
            : (isTrusted ? "" : "拖入后，打开 VoiceStick 右侧的开关；也可点列表下方的 ＋ 添加。")
        if let panel = window, panel.frame.height != preferredPanelHeight {
            panel.setContentSize(NSSize(width: panel.frame.width, height: preferredPanelHeight))
        }
    }

    private func trackSystemSettings() {
        guard presentationID != nil else { return }
        updatePermissionStatus()
        let settings = ["com.apple.systempreferences", "com.apple.SystemSettings"]
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .first
        guard let settings else {
            if didActivateSettings { close() }
            return
        }
        if settings.isActive {
            didActivateSettings = true
            if !isDraggingApp { positionPanel(settingsPID: settings.processIdentifier) }
            if window?.isVisible == false { window?.orderFrontRegardless() }
        } else if didActivateSettings, !isDraggingApp {
            window?.orderOut(nil)
        }
    }

    private func positionPanel(settingsPID: pid_t?) {
        guard let panel = window else { return }
        let settingsFrame = settingsPID.flatMap(Self.settingsWindowFrame)
        let screen = settingsFrame.flatMap { frame in
            NSScreen.screens.max { lhs, rhs in
                let left = lhs.frame.intersection(frame)
                let right = rhs.frame.intersection(frame)
                return left.width * left.height < right.width * right.height
            }
        } ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if let settingsFrame, let settingsPID, measuredSettingsFrame != settingsFrame {
            settingsSidebarWidth = Self.sidebarWidth(for: settingsPID, windowWidth: settingsFrame.width) ?? 232
            measuredSettingsFrame = settingsFrame
        }
        let frame = AccessibilityGuidePlacement.frame(
            settingsFrame: settingsFrame, visibleFrame: visible,
            sidebarWidth: settingsSidebarWidth, height: preferredPanelHeight
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private static func sidebarWidth(for pid: pid_t, windowWidth: CGFloat) -> CGFloat? {
        // Use the split position when already authorized; the guide must also work
        // before permission is granted, using the standard 232 pt sidebar fallback.
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let settingsWindow = unsafeBitCast(windowValue, to: AXUIElement.self)
        func children(of element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
            return value as? [AXUIElement] ?? []
        }
        func role(of element: AXUIElement) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
            return value as? String
        }
        guard let split = children(of: settingsWindow).prefix(4).first(where: { role(of: $0) == kAXSplitGroupRole }),
              let divider = children(of: split).prefix(8).first(where: { role(of: $0) == kAXSplitterRole }) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(divider, kAXValueAttribute as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        let width = CGFloat(number.doubleValue)
        return width.isFinite && width >= 160 && width < windowWidth - 240 ? width : nil
    }

    private static func settingsWindowFrame(for pid: pid_t) -> NSRect? {
        // Read window bounds only; no screenshot or Accessibility permission is needed.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryScreen = NSScreen.screens.first else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 400, rect.height >= 300 else { continue }
            return NSRect(x: rect.minX, y: primaryScreen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }
}

private final class DraggableApplicationView: NSView, NSDraggingSource {
    var onDraggingChanged: ((Bool) -> Void)?
    private let appURL: URL
    private var mouseDownPoint: NSPoint?

    init(appURL: URL) {
        self.appURL = appURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 1
        toolTip = "按住整条卡片，将 VoiceStick.app 拖入系统设置的权限列表"
        setAccessibilityElement(true)
        setAccessibilityLabel("VoiceStick 应用，拖到辅助功能权限列表")
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: appURL.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: "VoiceStick")
        name.font = .systemFont(ofSize: 16, weight: .medium)
        let row = NSStackView(views: [icon, name])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseDownPoint,
              hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 4 else { return }
        mouseDownPoint = nil
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let preview = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            preview.addRepresentation(bitmap)
        }
        item.setDraggingFrame(bounds, contents: preview)
        onDraggingChanged?(true)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDraggingChanged?(false)
    }
}
