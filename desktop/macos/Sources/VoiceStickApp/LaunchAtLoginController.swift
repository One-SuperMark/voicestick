import AppKit
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled, enabled, requiresApproval, unavailable, unsupported

    @available(macOS 13.0, *)
    static func fromSystemStatus(_ status: SMAppService.Status) -> Self {
        switch status {
        // A service the system has never seen can be notFound. It must remain
        // clickable so the user can register it for the first time. Actual
        // bundle/signature errors are reported by register(), not this lookup.
        case .notRegistered, .notFound: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        @unknown default: return .unavailable
        }
    }

    var canToggle: Bool {
        self == .disabled || self == .enabled || self == .requiresApproval
    }

    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }

    var menuState: NSControl.StateValue {
        switch self {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        default: return .off
        }
    }

    var title: String {
        self == .requiresApproval ? "开机启动（等待系统允许）" : "开机启动"
    }

    var toolTip: String {
        switch self {
        case .disabled: return "登录 Mac 后自动运行 VoiceStick。"
        case .enabled: return "已开启，登录 Mac 后自动运行；点击可关闭。"
        case .requiresApproval: return "请在系统登录项中允许 VoiceStick；点击本项可取消开机启动。"
        case .unavailable: return "无法读取登录项，请将 VoiceStick 安装到应用程序文件夹后重新打开。"
        case .unsupported: return "应用内开机启动开关需要 macOS 13 或更新版本。"
        }
    }
}

protocol LaunchAtLoginService {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

private final class SystemLaunchAtLoginService: LaunchAtLoginService {
    private var lastLoggedStatus: Int?

    var state: LaunchAtLoginState {
        guard #available(macOS 13.0, *) else { return .unsupported }
        let status = SMAppService.mainApp.status
        if lastLoggedStatus != status.rawValue {
            lastLoggedStatus = status.rawValue
            DiagnosticLog.write("login_item_status raw_status=\(status.rawValue)")
        }
        return .fromSystemStatus(status)
    }

    func register() throws {
        if #available(macOS 13.0, *) { try SMAppService.mainApp.register() }
    }

    func unregister() throws {
        if #available(macOS 13.0, *) { try SMAppService.mainApp.unregister() }
    }

    func openSystemSettings() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
    }
}

/// The system is the source of truth: never auto-register on launch or persist
/// a second boolean that could override a user's choice in System Settings.
final class LaunchAtLoginController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let service: LaunchAtLoginService
    private weak var toggleItem: NSMenuItem?
    private weak var approvalItem: NSMenuItem?

    init(service: LaunchAtLoginService? = nil) {
        self.service = service ?? SystemLaunchAtLoginService()
        super.init()
    }

    func addMenuItems(to menu: NSMenu) {
        let toggle = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: "power.circle", accessibilityDescription: "开机启动")
        toggle.image?.isTemplate = true
        menu.addItem(toggle)
        toggleItem = toggle

        let approval = NSMenuItem(title: "在系统设置中允许开机启动", action: #selector(openLoginItems), keyEquivalent: "")
        approval.target = self
        menu.addItem(approval)
        approvalItem = approval
        refresh()
    }

    func refresh() {
        let state = service.state
        toggleItem?.title = state.title
        toggleItem?.state = state.menuState
        toggleItem?.toolTip = state.toolTip
        toggleItem?.isEnabled = state.canToggle
        approvalItem?.isHidden = state != .requiresApproval
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === toggleItem { return service.state.canToggle }
        return menuItem === approvalItem && service.state == .requiresApproval
    }

    /// Re-read before acting and after success or failure; never show an
    /// optimistic checkmark when registration failed or needs approval.
    func toggleRegistration() throws {
        defer { refresh() }
        let state = service.state
        guard state.canToggle else { return }
        if state.isRegistered {
            try service.unregister()
        } else {
            try service.register()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try toggleRegistration()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法更改开机启动"
            alert.informativeText = service.state == .requiresApproval
                ? "macOS 尚未允许 VoiceStick 开机启动。请使用菜单中的系统设置入口确认；也可以再次点击开机启动来取消。"
                : "系统未能完成登录项变更，已重新读取实际状态。请确认应用位于应用程序文件夹后重试。\n\(error.localizedDescription)"
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openLoginItems() {
        guard service.state == .requiresApproval else { refresh(); return }
        service.openSystemSettings()
    }
}
