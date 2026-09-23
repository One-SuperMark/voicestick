import AppKit

/// A small floating drag source for adding this app to macOS Accessibility.
/// macOS requires the user to perform the final drop and enable the toggle.
final class AccessibilityPermissionPanelController: NSWindowController {
    init(appURL: URL = Bundle.main.bundleURL) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "添加 VoiceStick 权限"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "将 VoiceStick 拖入权限列表")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.alignment = .center

        let detail = NSTextField(wrappingLabelWithString: "把下方图标拖到“设备控制和数据访问”页面左下角的 +，再开启 VoiceStick。")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 3

        let appIcon = DraggableAppIconView(appURL: appURL)
        appIcon.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "按住图标拖拽")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center

        let stack = NSStackView(views: [title, detail, appIcon, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            appIcon.widthAnchor.constraint(equalToConstant: 58),
            appIcon.heightAnchor.constraint(equalToConstant: 58)
        ])
        panel.contentView = content
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class DraggableAppIconView: NSImageView, NSDraggingSource {
    private let appURL: URL

    init(appURL: URL) {
        self.appURL = appURL
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: appURL.path)
        imageScaling = .scaleProportionallyUpOrDown
        toolTip = "拖拽 VoiceStick.app 到系统设置"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
