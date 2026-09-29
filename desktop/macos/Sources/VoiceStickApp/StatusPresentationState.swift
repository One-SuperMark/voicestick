import Foundation

enum VoiceStickStatus: Equatable {
    case needsPairing
    case searching
    case disconnected
    case preparing
    case listening
    case processing
    case ready
    case error
    case idle

    init(text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("error") || normalized.contains("failed") ||
            normalized.contains("failure") || normalized.contains("错误") ||
            normalized.contains("失败") {
            self = .error
        } else if normalized.contains("pair") || normalized.contains("配对") {
            self = .needsPairing
        } else if normalized.contains("disconnect") || normalized.contains("not connected") ||
                    normalized.contains("no connected device") || normalized.contains("断开") ||
                    normalized.contains("未连接") {
            self = .disconnected
        } else if normalized.contains("search") || normalized.contains("scan") ||
                    normalized.contains("搜索") || normalized.contains("扫描") {
            self = .searching
        } else if normalized.contains("prepar") || normalized.contains("connect") ||
                    normalized.contains("正在准备") || normalized.contains("准备中") ||
                    normalized.contains("连接中") || normalized.contains("已连接") {
            self = .preparing
        } else if normalized.contains("process") || normalized.contains("final") ||
                    normalized.contains("transcrib") || normalized.contains("translat") ||
                    normalized.contains("处理") || normalized.contains("正在识别") ||
                    normalized.contains("识别中") || normalized.contains("翻译") {
            self = .processing
        } else if normalized.contains("listen") || normalized.contains("record") ||
                    normalized.contains("录音") {
            self = .listening
        } else if normalized.contains("ready") || normalized.contains("准备就绪") ||
                    normalized.contains("已就绪") || normalized.contains("pause") ||
                    normalized.contains("no speech") || normalized.contains("未检测") {
            self = .ready
        } else {
            self = .idle
        }
    }

    func symbolName(hasConnectedDevices: Bool) -> String {
        switch self {
        case .needsPairing:
            return "dot.radiowaves.left.and.right"
        case .searching:
            return "antenna.radiowaves.left.and.right"
        case .disconnected:
            return "link.circle"
        case .preparing:
            return "arrow.triangle.2.circlepath"
        case .listening:
            return "mic.fill"
        case .processing:
            return "waveform"
        case .ready:
            return hasConnectedDevices ? "link.circle.fill" : "link.circle"
        case .error:
            return "exclamationmark.triangle"
        case .idle:
            return hasConnectedDevices ? "link.circle" : "dot.radiowaves.left.and.right"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .needsPairing:
            return "请配对 VoiceStick"
        case .searching:
            return "正在搜索 VoiceStick"
        case .disconnected:
            return "设备未连接"
        case .preparing:
            return "正在准备"
        case .listening:
            return "正在录音"
        case .processing:
            return "正在处理"
        case .ready:
            return "准备就绪"
        case .error:
            return "发生错误"
        case .idle:
            return "等待设备状态"
        }
    }

    var visibleTitle: String? {
        switch self {
        case .needsPairing:
            return "配对"
        case .searching:
            return "Searching…"
        case .disconnected:
            return "Disconnected"
        case .preparing:
            return "Preparing…"
        case .processing:
            return "Processing"
        case .error:
            return "错误"
        case .listening, .ready, .idle:
            return nil
        }
    }
}

struct StatusPresentationState {
    private struct Activity {
        let status: VoiceStickStatus
        let deviceID: String?
    }

    private var pairedDeviceIDs: Set<String>
    private var connectedDeviceIDs: Set<String> = []
    private var transportReadyDeviceIDs: Set<String> = []
    // One independent entry per device, plus an optional global entry, in recency order.
    private var activities: [Activity] = []

    init(pairedDeviceIDs: Set<String>) {
        self.pairedDeviceIDs = pairedDeviceIDs
    }

    var displayedStatus: VoiceStickStatus {
        guard !connectedDeviceIDs.isEmpty else {
            return pairedDeviceIDs.isEmpty ? .needsPairing : .disconnected
        }
        if let activity = activities.last {
            return activity.status
        }
        return transportReadyDeviceIDs.isEmpty ? .preparing : .ready
    }

    mutating func setPairedDeviceIDs(_ ids: Set<String>) {
        pairedDeviceIDs = ids
    }

    @discardableResult
    mutating func updateConnections(_ ids: Set<String>) -> Set<String> {
        let lostDeviceIDs = connectedDeviceIDs.subtracting(ids)
        connectedDeviceIDs = ids
        transportReadyDeviceIDs.formIntersection(ids)
        activities.removeAll { activity in
            if let deviceID = activity.deviceID {
                return !ids.contains(deviceID)
            }
            return ids.isEmpty
        }
        return lostDeviceIDs
    }

    mutating func setStatus(_ status: VoiceStickStatus, deviceID: String? = nil) {
        if let deviceID, !connectedDeviceIDs.contains(deviceID) {
            return
        }
        switch status {
        case .listening, .processing, .error:
            guard !connectedDeviceIDs.isEmpty else { return }
            activities.removeAll { $0.deviceID == deviceID }
            activities.append(Activity(status: status, deviceID: deviceID))
        case .ready, .idle:
            activities.removeAll { $0.deviceID == deviceID }
        case .needsPairing, .searching, .disconnected, .preparing:
            // Connection presentation is derived from facts, not descriptive text.
            break
        }
    }

    mutating func markTransportReady(_ deviceID: String) {
        guard connectedDeviceIDs.contains(deviceID) else { return }
        transportReadyDeviceIDs.insert(deviceID)
    }
}
