import AppKit

final class StatusController {
    private enum AppStatus {
        case needsPairing
        case listening
        case processing
        case ready
        case error

        init(text: String) {
            let normalized = text.lowercased()
            if normalized.contains("pair") || normalized.contains("配对") {
                self = .needsPairing
            } else if normalized.contains("listen") || normalized.contains("录音") {
                self = .listening
            } else if normalized.contains("error") || normalized.contains("failed") || normalized.contains("错误") || normalized.contains("失败") {
                self = .error
            } else if normalized.contains("process") || normalized.contains("final") || normalized.contains("transcrib") || normalized.contains("处理") {
                self = .processing
            } else if normalized.contains("ready") ||
                        normalized.contains("connect") ||
                        normalized.contains("scan") ||
                        normalized.contains("match") ||
                        normalized.contains("pause") ||
                        normalized.contains("no speech") ||
                        normalized.contains("准备") ||
                        normalized.contains("未检测") {
                self = .ready
            } else {
                self = .processing
            }
        }

        func symbolName(hasConnectedDevices: Bool) -> String {
            switch self {
            case .needsPairing:
                return "dot.radiowaves.left.and.right"
            case .listening:
                return "mic.fill"
            case .processing:
                return "waveform"
            case .ready:
                if !hasConnectedDevices {
                    return "dot.radiowaves.left.and.right"
                }
                return "link.circle.fill"
            case .error:
                return "exclamationmark.triangle"
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .needsPairing:
                return "请配对 VoiceStick"
            case .listening:
                return "正在录音"
            case .processing:
                return "正在处理"
            case .ready:
                return "准备就绪"
            case .error:
                return "发生错误"
            }
        }

        var visibleTitle: String? {
            switch self {
            case .needsPairing:
                return "配对"
            case .processing:
                return "Processing"
            case .error:
                return "错误"
            case .listening, .ready:
                return nil
            }
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var overlays: [String: OverlayController] = [:]
    private var visibleOverlayKeys: Set<String> = []

    var onQuit: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onPairDevice: (() -> Void)?
    var onForgetDevice: ((String) -> Void)?
    var onUpdateFirmwareDevice: ((String) -> Void)?
    var onSetDeviceThemeColor: ((String, OverlayThemeColor) -> Void)?
    var onSetDeviceOverlayPosition: ((String, OverlayPosition) -> Void)?
    var onRestoreLastInput: (() -> Bool)?
    var onSetInteractionMode: ((InteractionMode) -> Void)?
    var onSetAutoEnter: ((Bool) -> Void)?
    var onSetSideEnter: ((Bool) -> Void)?
    var onSetSideDelete: ((Bool) -> Void)?
    var onSetSideRestoreLastInput: ((Bool) -> Void)?
    var onSetPrimaryEnter: ((Bool) -> Void)?
    var onSetDefaultOutputProfile: ((OutputProfile) -> Void)?
    var onSetDeviceOutputProfile: ((String, OutputProfile) -> Void)?
    private var needsPairing: Bool
    private var hasRecoverableInput = false
    private var pairedDeviceIDs: [String]
    private var deviceThemeColors: [String: OverlayThemeColor]
    private var deviceOverlayPositions: [String: OverlayPosition]
    private var connectedDevices: [ConnectedVoiceStickDevice] = []
    private var firmwareInfoByDeviceID: [String: DeviceFirmwareInfo] = [:]
    private var interactionMode: InteractionMode
    private var autoEnter: Bool
    private var sideEnter: Bool
    private var sideDelete: Bool
    private var sideRestoreLastInput: Bool
    private var primaryEnter: Bool
    private var defaultOutputProfile: OutputProfile
    private var deviceOutputProfiles: [String: OutputProfile]

    init(pairedDeviceIDs: [String] = [],
         deviceThemeColors: [String: OverlayThemeColor] = [:],
         deviceOverlayPositions: [String: OverlayPosition] = [:],
         interactionMode: InteractionMode = .holdToTalk,
         autoEnter: Bool = true,
         sideEnter: Bool = false,
         sideDelete: Bool = false,
         sideRestoreLastInput: Bool = true,
         primaryEnter: Bool = false,
         defaultOutputProfile: OutputProfile = .default,
         deviceOutputProfiles: [String: OutputProfile] = [:]) {
        self.pairedDeviceIDs = pairedDeviceIDs
        self.deviceThemeColors = deviceThemeColors
        self.deviceOverlayPositions = deviceOverlayPositions
        self.interactionMode = interactionMode
        self.autoEnter = autoEnter
        self.sideEnter = autoEnter ? false : sideEnter
        self.sideDelete = sideDelete
        self.sideRestoreLastInput = sideDelete ? false : sideRestoreLastInput
        self.primaryEnter = autoEnter || sideEnter ? false : primaryEnter
        self.defaultOutputProfile = defaultOutputProfile
        self.deviceOutputProfiles = deviceOutputProfiles
        self.needsPairing = pairedDeviceIDs.isEmpty
        updateStatusButton(.ready)
        rebuildMenu()
    }

    func setPairedDeviceIDs(_ deviceIDs: [String]) {
        pairedDeviceIDs = deviceIDs
        deviceThemeColors = deviceThemeColors.filter { deviceIDs.contains($0.key) }
        deviceOverlayPositions = deviceOverlayPositions.filter { deviceIDs.contains($0.key) }
        deviceOutputProfiles = deviceOutputProfiles.filter { deviceIDs.contains($0.key) }
        needsPairing = deviceIDs.isEmpty
        rebuildMenu()
    }

    func setDeviceThemeColors(_ colors: [String: OverlayThemeColor]) {
        deviceThemeColors = colors.filter { pairedDeviceIDs.contains($0.key) }
        rebuildMenu()
    }

    func setDeviceOverlayPositions(_ positions: [String: OverlayPosition]) {
        deviceOverlayPositions = positions.filter { pairedDeviceIDs.contains($0.key) }
        rebuildMenu()
    }

    func setConnectedDevices(_ devices: [ConnectedVoiceStickDevice]) {
        let sortedDevices = devices.sorted { $0.deviceID < $1.deviceID }
        guard connectedDevices.map(\.deviceID) != sortedDevices.map(\.deviceID) ||
                connectedDevices.map(\.name) != sortedDevices.map(\.name) else { return }
        connectedDevices = sortedDevices
        rebuildMenu()
    }

    func setFirmwareInfo(_ infoByDeviceID: [String: DeviceFirmwareInfo]) {
        firmwareInfoByDeviceID = infoByDeviceID
        rebuildMenu()
    }

    func setHasRecoverableInput(_ hasRecoverableInput: Bool) {
        guard self.hasRecoverableInput != hasRecoverableInput else { return }
        self.hasRecoverableInput = hasRecoverableInput
        rebuildMenu()
    }

    func setInputOptions(interactionMode: InteractionMode, autoEnter: Bool, sideEnter: Bool, sideDelete: Bool, sideRestoreLastInput: Bool, primaryEnter: Bool) {
        let normalizedSideEnter = autoEnter ? false : sideEnter
        let normalizedPrimaryEnter = autoEnter || normalizedSideEnter || interactionMode == .clickToTalk ? false : primaryEnter
        guard self.interactionMode != interactionMode ||
                self.autoEnter != autoEnter ||
                self.sideEnter != normalizedSideEnter ||
                self.sideDelete != sideDelete ||
                self.sideRestoreLastInput != (sideDelete ? false : sideRestoreLastInput) ||
                self.primaryEnter != normalizedPrimaryEnter else { return }
        self.interactionMode = interactionMode
        self.autoEnter = autoEnter
        self.sideEnter = normalizedSideEnter
        self.sideDelete = sideDelete
        self.sideRestoreLastInput = sideDelete ? false : sideRestoreLastInput
        self.primaryEnter = normalizedPrimaryEnter
        rebuildMenu()
    }

    func setDefaultOutputProfile(_ profile: OutputProfile) {
        guard defaultOutputProfile != profile else { return }
        defaultOutputProfile = profile
        rebuildMenu()
    }

    func setDeviceOutputProfiles(_ profiles: [String: OutputProfile]) {
        deviceOutputProfiles = profiles.filter { pairedDeviceIDs.contains($0.key) }
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if hasRecoverableInput, sideRestoreLastInput {
            menu.addItem(makeMenuItem(
                title: "恢复最近一次输入",
                symbolName: "arrow.uturn.backward",
                action: #selector(restoreLastInput)
            ))
            menu.addItem(NSMenuItem.separator())
        }

        addDeviceItems()

        addInputItems()

        menu.addItem(makeMenuItem(
            title: "配对设备…",
            symbolName: "dot.radiowaves.left.and.right",
            action: #selector(pairDevice)
        ))

        menu.addItem(makeMenuItem(
            title: "设置…",
            symbolName: "gearshape",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))

        menu.addItem(makeMenuItem(
            title: "打开辅助功能设置",
            symbolName: "accessibility",
            action: #selector(openAccessibilitySettings)
        ))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let versionItem = NSMenuItem(title: "当前版本：\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        versionItem.image = Self.symbolImage(named: "info.circle", accessibilityDescription: versionItem.title)
        menu.addItem(versionItem)

        menu.addItem(makeMenuItem(
            title: "退出 VoiceStick",
            symbolName: "power",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private func addInputItems() {
        addOutputItems()

        let interactionItem = makeMenuItem(
            title: "交互方式",
            symbolName: "hand.tap",
            action: nil
        )
        let interactionSubmenu = NSMenu()
        let holdItem = makeMenuItem(
            title: InteractionMode.holdToTalk.displayName,
            symbolName: "hand.tap",
            action: #selector(selectInteractionMode)
        )
        holdItem.representedObject = InteractionMode.holdToTalk.rawValue
        holdItem.state = interactionMode == .holdToTalk ? .on : .off
        interactionSubmenu.addItem(holdItem)

        let clickItem = makeMenuItem(
            title: InteractionMode.clickToTalk.displayName,
            symbolName: "cursorarrow.click",
            action: #selector(selectInteractionMode)
        )
        clickItem.representedObject = InteractionMode.clickToTalk.rawValue
        clickItem.state = interactionMode == .clickToTalk ? .on : .off
        interactionSubmenu.addItem(clickItem)

        interactionItem.submenu = interactionSubmenu
        menu.addItem(interactionItem)
        menu.addItem(NSMenuItem.separator())

        let afterPasteItem = makeMenuItem(
            title: "粘贴后按回车",
            symbolName: "return",
            action: #selector(toggleAutoEnter)
        )
        afterPasteItem.state = autoEnter ? .on : .off
        menu.addItem(afterPasteItem)

        let sideEnterItem = makeMenuItem(
            title: "侧键点击发送",
            symbolName: "rectangle.portrait.and.arrow.right",
            action: #selector(toggleSideEnter)
        )
        sideEnterItem.state = sideEnter ? .on : .off
        menu.addItem(sideEnterItem)

        let primaryEnterItem = makeMenuItem(
            title: "前键点击发送",
            symbolName: "hand.tap",
            action: #selector(togglePrimaryEnter)
        )
        primaryEnterItem.state = primaryEnter ? .on : .off
        menu.addItem(primaryEnterItem)
        menu.addItem(NSMenuItem.separator())

        let sideDeleteItem = makeMenuItem(
            title: "侧键删除",
            symbolName: "delete.left",
            action: #selector(toggleSideDelete)
        )
        sideDeleteItem.state = sideDelete ? .on : .off
        menu.addItem(sideDeleteItem)

        let sideRestoreLastInputItem = makeMenuItem(
            title: "侧键恢复上一次输入",
            symbolName: "arrow.uturn.backward",
            action: #selector(toggleSideRestoreLastInput)
        )
        sideRestoreLastInputItem.state = sideRestoreLastInput ? .on : .off
        menu.addItem(sideRestoreLastInputItem)
        menu.addItem(NSMenuItem.separator())
    }

    private func addOutputItems() {
        let outputItem = makeMenuItem(
            title: "输出位置",
            symbolName: "text.bubble",
            action: nil
        )
        let outputSubmenu = NSMenu()
        for target in OutputTarget.allCases {
            let item = NSMenuItem(
                title: target.displayName,
                action: #selector(selectOutputTarget),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = target.rawValue
            item.state = defaultOutputProfile.target == target ? .on : .off
            outputSubmenu.addItem(item)
        }
        outputItem.submenu = outputSubmenu
        menu.addItem(outputItem)
    }

    private func addDeviceItems() {
        guard !pairedDeviceIDs.isEmpty else { return }

        let connectedByID = Dictionary(uniqueKeysWithValues: connectedDevices.map { ($0.deviceID, $0) })
        for deviceID in pairedDeviceIDs.sorted() {
            let connectedDevice = connectedByID[deviceID]
            let title = connectedDevice?.name ?? "VS-\(deviceID)"
            let deviceItem = makeMenuItem(
                title: title,
                symbolName: connectedDevice == nil ? "link.circle" : "link.circle.fill",
                action: nil
            )
            let submenu = NSMenu()
            let stateItem = NSMenuItem(
                title: connectedDevice == nil ? "正在扫描" : "已连接",
                action: nil,
                keyEquivalent: ""
            )
            stateItem.isEnabled = false
            stateItem.image = Self.symbolImage(
                named: connectedDevice == nil ? "antenna.radiowaves.left.and.right" : "checkmark.circle",
                accessibilityDescription: stateItem.title
            )
            submenu.addItem(stateItem)
            submenu.addItem(NSMenuItem.separator())

            addThemeColorItems(to: submenu, deviceID: deviceID)
            addOverlayPositionItems(to: submenu, deviceID: deviceID)
            addDeviceTextItems(to: submenu, deviceID: deviceID)
            submenu.addItem(NSMenuItem.separator())

            addFirmwareItems(to: submenu, deviceID: deviceID, isConnected: connectedDevice != nil)

            let forgetItem = makeMenuItem(
                title: "忽略此设备",
                symbolName: "xmark.circle",
                action: #selector(forgetConnectedDevice)
            )
            forgetItem.representedObject = deviceID
            submenu.addItem(forgetItem)
            deviceItem.submenu = submenu
            menu.addItem(deviceItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addThemeColorItems(to submenu: NSMenu, deviceID: String) {
        let currentColor = deviceThemeColors[deviceID] ?? .white
        let themeItem = makeMenuItem(
            title: "主题颜色",
            symbolName: "paintpalette",
            action: nil
        )
        let themeSubmenu = NSMenu()
        for color in OverlayThemeColor.allCases {
            let colorItem = NSMenuItem(
                title: color.displayName,
                action: #selector(selectDeviceThemeColor),
                keyEquivalent: ""
            )
            colorItem.target = self
            colorItem.representedObject = "\(deviceID):\(color.rawValue)"
            colorItem.state = currentColor == color ? .on : .off
            themeSubmenu.addItem(colorItem)
        }
        themeItem.submenu = themeSubmenu
        submenu.addItem(themeItem)
    }

    private func addOverlayPositionItems(to submenu: NSMenu, deviceID: String) {
        let currentPosition = deviceOverlayPositions[deviceID] ?? .center
        let positionItem = makeMenuItem(
            title: "字幕位置",
            symbolName: "rectangle.inset.filled",
            action: nil
        )
        let positionSubmenu = NSMenu()
        for position in OverlayPosition.allCases {
            let item = NSMenuItem(
                title: position.displayName,
                action: #selector(selectDeviceOverlayPosition),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = "\(deviceID):\(position.rawValue)"
            item.state = currentPosition == position ? .on : .off
            positionSubmenu.addItem(item)
        }
        positionItem.submenu = positionSubmenu
        submenu.addItem(positionItem)
    }

    private func addDeviceTextItems(to submenu: NSMenu, deviceID: String) {
        let profile = outputProfile(for: deviceID)
        let textItem = makeMenuItem(
            title: "文本转换",
            symbolName: "textformat",
            action: nil
        )
        let textSubmenu = NSMenu()
        let originalItem = NSMenuItem(
            title: "原文",
            action: #selector(selectDeviceTextMode),
            keyEquivalent: ""
        )
        originalItem.target = self
        originalItem.representedObject = "\(deviceID):original:"
        originalItem.state = profile.transform == .original ? .on : .off
        textSubmenu.addItem(originalItem)
        textSubmenu.addItem(NSMenuItem.separator())

        for language in Self.translationTargets {
            let item = NSMenuItem(
                title: "翻译为\(language.name)",
                action: #selector(selectDeviceTextMode),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = "\(deviceID):translate:\(language.code)"
            item.state = profile.transform == .translate && profile.translationTarget == language.code ? .on : .off
            textSubmenu.addItem(item)
        }
        textItem.submenu = textSubmenu
        submenu.addItem(textItem)
    }

    private func addFirmwareItems(to submenu: NSMenu, deviceID: String, isConnected: Bool) {
        let info = firmwareInfoByDeviceID[deviceID]
        let currentTitle: String
        if let version = info?.currentVersion {
            currentTitle = "固件版本 \(version)"
        } else if isConnected {
            currentTitle = "正在读取固件版本"
        } else {
            currentTitle = "固件版本暂不可用"
        }
        let currentItem = NSMenuItem(title: currentTitle, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        currentItem.image = Self.symbolImage(named: "info.circle", accessibilityDescription: currentTitle)
        submenu.addItem(currentItem)

        if info?.isChecking == true {
            let checkingItem = NSMenuItem(title: "正在检查固件更新", action: nil, keyEquivalent: "")
            checkingItem.isEnabled = false
            checkingItem.image = Self.symbolImage(named: "arrow.triangle.2.circlepath", accessibilityDescription: "正在检查")
            submenu.addItem(checkingItem)
            return
        }

        if let errorMessage = info?.errorMessage {
            let errorItem = NSMenuItem(title: "固件更新检查失败", action: nil, keyEquivalent: "")
            errorItem.toolTip = errorMessage
            errorItem.isEnabled = false
            errorItem.image = Self.symbolImage(named: "exclamationmark.triangle", accessibilityDescription: "固件更新检查失败")
            submenu.addItem(errorItem)
            return
        }

        if info?.updateAvailable == true, let latestVersion = info?.latestVersion {
            let updateItem = makeMenuItem(
                title: "更新到 \(latestVersion)…",
                symbolName: "square.and.arrow.down",
                action: #selector(updateFirmwareForDevice)
            )
            updateItem.representedObject = deviceID
            updateItem.isEnabled = isConnected
            submenu.addItem(updateItem)
        } else if info?.latestVersion != nil && info?.currentVersion != nil {
            let upToDateItem = NSMenuItem(title: "固件已是最新", action: nil, keyEquivalent: "")
            upToDateItem.isEnabled = false
            upToDateItem.image = Self.symbolImage(named: "checkmark.circle", accessibilityDescription: "固件已是最新")
            submenu.addItem(upToDateItem)
        }
    }

    func setStatus(_ text: String) {
        DispatchQueue.main.async {
            self.updateStatusButton(AppStatus(text: text))
        }
    }

    func showListening(deviceID: String? = nil) {
        setStatus("正在录音")
        let overlay = overlay(for: deviceID)
        markOverlayVisible(for: deviceID)
        applyOverlayStyle(for: deviceID, overlay: overlay)
        overlay.showListening(text: "")
    }

    func showPartial(_ text: String, deviceID: String? = nil) {
        setStatus(text.isEmpty ? "正在录音" : text)
        let overlay = overlay(for: deviceID)
        markOverlayVisible(for: deviceID)
        applyOverlayStyle(for: deviceID, overlay: overlay)
        overlay.showListening(text: text)
    }

    func showFinal(_ text: String, deviceID: String? = nil, onHidden: (() -> Void)? = nil) {
        setStatus(text.isEmpty ? "未检测到语音" : "准备就绪")
        let overlay = overlay(for: deviceID)
        markOverlayVisible(for: deviceID)
        applyOverlayStyle(for: deviceID, overlay: overlay)
        overlay.showFinal(text: text, onHidden: { [weak self] in
            self?.markOverlayHidden(for: deviceID)
            onHidden?()
        })
    }

    func showPausedFinal(_ text: String, deviceID: String? = nil) {
        let overlay = overlay(for: deviceID)
        markOverlayVisible(for: deviceID)
        applyOverlayStyle(for: deviceID, overlay: overlay)
        overlay.showPaused(text: text)
    }

    func showError(_ text: String, deviceID: String? = nil, onHidden: (() -> Void)? = nil) {
        setStatus("语音识别错误：\(text)")
        let overlay = overlay(for: deviceID)
        markOverlayVisible(for: deviceID)
        applyOverlayStyle(for: deviceID, overlay: overlay)
        overlay.showError(text, onHidden: { [weak self] in
            self?.markOverlayHidden(for: deviceID)
            onHidden?()
        })
    }

    func hideOverlay(onHidden: (() -> Void)? = nil) {
        let overlayList = overlays.values
        visibleOverlayKeys.removeAll()
        var remaining = overlayList.count
        guard remaining > 0 else {
            onHidden?()
            return
        }
        for overlay in overlayList {
            overlay.hide {
                remaining -= 1
                if remaining == 0 {
                    onHidden?()
                }
            }
        }
    }

    func hideOverlay(deviceID: String?, onHidden: (() -> Void)? = nil) {
        let key = overlayKey(for: deviceID)
        visibleOverlayKeys.remove(key)
        updateOverlayStackIndices()
        guard let overlay = overlays[key] else {
            onHidden?()
            return
        }
        overlay.hide(onHidden: onHidden)
    }

    private func updateStatusButton(_ status: AppStatus) {
        guard let button = statusItem.button else { return }
        button.image = Self.symbolImage(
            named: status.symbolName(hasConnectedDevices: !connectedDevices.isEmpty),
            accessibilityDescription: status.accessibilityDescription
        )
        button.title = status.visibleTitle ?? ""
        button.imagePosition = status.visibleTitle == nil ? .imageOnly : .imageLeading
        button.toolTip = "VoiceStick：\(status.accessibilityDescription)"
        button.setAccessibilityLabel("VoiceStick：\(status.accessibilityDescription)")
    }

    private func makeMenuItem(
        title: String,
        symbolName: String,
        action: Selector?,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = Self.symbolImage(named: symbolName, accessibilityDescription: title)
        return item
    }

    private static func symbolImage(named name: String, accessibilityDescription: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private static let translationTargets: [(code: String, name: String)] = [
        ("en", "英语"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁体中文"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("ru", "俄语"),
        ("fr", "法语"),
        ("de", "德语"),
        ("es", "西班牙语"),
        ("it", "意大利语"),
        ("pt", "葡萄牙语"),
        ("nl", "荷兰语"),
        ("sv", "瑞典语"),
        ("pl", "波兰语"),
        ("tr", "土耳其语"),
        ("ar", "阿拉伯语"),
        ("hi", "印地语"),
        ("id", "印度尼西亚语"),
        ("vi", "越南语"),
        ("th", "泰语")
    ]

    private func themeColor(for deviceID: String?) -> OverlayThemeColor {
        guard let deviceID else { return .white }
        return deviceThemeColors[AppConfig.normalizedDeviceID(deviceID)] ?? .white
    }

    private func overlayPosition(for deviceID: String?) -> OverlayPosition {
        guard let deviceID else { return .center }
        return deviceOverlayPositions[AppConfig.normalizedDeviceID(deviceID)] ?? .center
    }

    private func overlayKey(for deviceID: String?) -> String {
        guard let deviceID else { return "__default__" }
        return AppConfig.normalizedDeviceID(deviceID)
    }

    private func overlay(for deviceID: String?) -> OverlayController {
        let key = overlayKey(for: deviceID)
        if let overlay = overlays[key] {
            return overlay
        }
        let overlay = OverlayController()
        overlays[key] = overlay
        return overlay
    }

    private func markOverlayVisible(for deviceID: String?) {
        visibleOverlayKeys.insert(overlayKey(for: deviceID))
        updateOverlayStackIndices()
    }

    private func markOverlayHidden(for deviceID: String?) {
        visibleOverlayKeys.remove(overlayKey(for: deviceID))
        updateOverlayStackIndices()
    }

    private func updateOverlayStackIndices() {
        let groupedKeys = Dictionary(grouping: visibleOverlayKeys) { key in
            overlayPosition(for: deviceID(forOverlayKey: key))
        }
        for keys in groupedKeys.values {
            for (index, key) in keys.sorted().enumerated() {
                overlays[key]?.setStackIndex(index)
            }
        }
    }

    private func deviceID(forOverlayKey key: String) -> String? {
        key == "__default__" ? nil : key
    }

    private func outputProfile(for deviceID: String) -> OutputProfile {
        guard let deviceProfile = deviceOutputProfiles[AppConfig.normalizedDeviceID(deviceID)] else {
            return defaultOutputProfile
        }
        return OutputProfile(
            target: defaultOutputProfile.target,
            transform: deviceProfile.transform,
            translationTarget: deviceProfile.translationTarget
        )
    }

    private func applyOverlayStyle(for deviceID: String?, overlay: OverlayController) {
        overlay.setThemeColor(themeColor(for: deviceID))
        overlay.setPosition(overlayPosition(for: deviceID))
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openAccessibilitySettings() {
        onOpenAccessibilitySettings?()
    }

    @objc private func pairDevice() {
        onPairDevice?()
    }

    @objc private func forgetConnectedDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        onForgetDevice?(deviceID)
    }

    @objc private func updateFirmwareForDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        onUpdateFirmwareDevice?(deviceID)
    }

    @objc private func selectDeviceThemeColor(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? String else { return }
        let parts = selection.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let color = OverlayThemeColor(rawValue: parts[1]) else { return }
        let deviceID = AppConfig.normalizedDeviceID(parts[0])
        if color == .white {
            deviceThemeColors.removeValue(forKey: deviceID)
        } else {
            deviceThemeColors[deviceID] = color
        }
        rebuildMenu()
        onSetDeviceThemeColor?(deviceID, color)
    }

    @objc private func selectDeviceOverlayPosition(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? String else { return }
        let parts = selection.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let position = OverlayPosition(rawValue: parts[1]) else { return }
        let deviceID = AppConfig.normalizedDeviceID(parts[0])
        if position == .center {
            deviceOverlayPositions.removeValue(forKey: deviceID)
        } else {
            deviceOverlayPositions[deviceID] = position
        }
        rebuildMenu()
        onSetDeviceOverlayPosition?(deviceID, position)
    }

    @objc private func selectDeviceTextMode(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? String else { return }
        let parts = selection.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2,
              let transform = TextTransform(rawValue: parts[1]) else { return }
        let deviceID = AppConfig.normalizedDeviceID(parts[0])
        var profile = outputProfile(for: deviceID)
        profile.transform = transform
        if transform == .translate, parts.count == 3, !parts[2].isEmpty {
            profile.translationTarget = parts[2]
        }
        setDeviceOutputProfile(deviceID: deviceID, profile: profile)
    }

    private func setDeviceOutputProfile(deviceID: String, profile: OutputProfile) {
        let storedProfile = OutputProfile(
            target: defaultOutputProfile.target,
            transform: profile.transform,
            translationTarget: profile.translationTarget
        )
        if storedProfile.transform == defaultOutputProfile.transform &&
            storedProfile.translationTarget == defaultOutputProfile.translationTarget {
            deviceOutputProfiles.removeValue(forKey: deviceID)
        } else {
            deviceOutputProfiles[deviceID] = storedProfile
        }
        rebuildMenu()
        onSetDeviceOutputProfile?(deviceID, storedProfile)
    }

    @objc private func restoreLastInput() {
        _ = onRestoreLastInput?()
    }

    @objc private func selectInteractionMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = InteractionMode(rawValue: rawValue)
        else { return }
        interactionMode = mode
        if mode == .clickToTalk {
            primaryEnter = false
        }
        rebuildMenu()
        onSetInteractionMode?(mode)
    }

    @objc private func toggleAutoEnter() {
        autoEnter.toggle()
        if autoEnter {
            sideEnter = false
            primaryEnter = false
        }
        rebuildMenu()
        onSetAutoEnter?(autoEnter)
    }

    @objc private func toggleSideEnter() {
        sideEnter.toggle()
        if sideEnter {
            autoEnter = false
            primaryEnter = false
        }
        rebuildMenu()
        onSetSideEnter?(sideEnter)
    }

    @objc private func toggleSideDelete() {
        sideDelete.toggle()
        if sideDelete {
            sideRestoreLastInput = false
        }
        rebuildMenu()
        onSetSideDelete?(sideDelete)
    }

    @objc private func toggleSideRestoreLastInput() {
        sideRestoreLastInput.toggle()
        if sideRestoreLastInput {
            sideDelete = false
        }
        rebuildMenu()
        onSetSideRestoreLastInput?(sideRestoreLastInput)
    }

    @objc private func togglePrimaryEnter() {
        primaryEnter.toggle()
        if primaryEnter {
            autoEnter = false
            sideEnter = false
            interactionMode = .holdToTalk
        }
        rebuildMenu()
        onSetPrimaryEnter?(primaryEnter)
    }

    @objc private func selectOutputTarget(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let target = OutputTarget(rawValue: rawValue)
        else { return }
        defaultOutputProfile.target = target
        rebuildMenu()
        onSetDefaultOutputProfile?(defaultOutputProfile)
    }

    @objc private func quitApp() {
        onQuit?()
    }
}
