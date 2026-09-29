import XCTest
@testable import VoiceStickApp

final class StatusPresentationStateTests: XCTestCase {
    private func state(paired: Set<String> = ["A", "B"]) -> StatusPresentationState {
        StatusPresentationState(pairedDeviceIDs: paired)
    }

    func testErrorsTakePriorityOverPairing() {
        for text in ["Pair save failed", "Pairing error", "配对失败", "语音识别错误"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .error, text)
        }
    }

    func testPairingTextHasItsOwnState() {
        for text in ["Pair a VoiceStick", "请配对 VoiceStick", "需要配对设备"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .needsPairing, text)
        }
    }

    func testDisconnectedTakesPriorityOverConnect() {
        for text in ["Disconnected", "Not connected", "设备已断开", "设备未连接"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .disconnected, text)
        }
    }

    func testSearchAndScanDoNotMeanProcessingOrReady() {
        for text in ["Searching…", "Scanning", "正在搜索 VoiceStick", "正在扫描"] {
            let status = VoiceStickStatus(text: text)
            XCTAssertEqual(status, .searching, text)
            XCTAssertNotEqual(status, .processing, text)
            XCTAssertNotEqual(status, .ready, text)
        }
    }

    func testPreparingAndConnectingHaveTheirOwnState() {
        for text in ["Preparing…", "Connecting", "Connected", "正在准备", "准备中", "已连接"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .preparing, text)
        }
    }

    func testExplicitRecognitionStagesStillMapCorrectly() {
        for text in ["Listening…", "Recording", "正在录音"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .listening, text)
        }
        for text in ["Processing", "Finalizing", "Transcribing", "Translating", "处理中", "正在识别"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .processing, text)
        }
        for text in ["Ready", "准备就绪", "No speech", "Paused"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .ready, text)
        }
    }

    func testUnknownAndPartialTextDoNotDefaultToProcessing() {
        for text in ["", "   ", "hello world", "这是测试用的部分文本", "a new sentence"] {
            XCTAssertEqual(VoiceStickStatus(text: text), .idle, text)
        }
    }

    func testMappingIgnoresCaseAndSurroundingWhitespace() {
        XCTAssertEqual(VoiceStickStatus(text: " \n DISCONNECTED \t"), .disconnected)
        XCTAssertEqual(VoiceStickStatus(text: "  pRePaRiNg...  "), .preparing)
        XCTAssertEqual(VoiceStickStatus(text: " \tTRANSLATING\n"), .processing)
    }

    func testConnectionPresentationUsesEnglishTitlesAndChineseDescriptions() {
        XCTAssertEqual(VoiceStickStatus.disconnected.visibleTitle, "Disconnected")
        XCTAssertEqual(VoiceStickStatus.preparing.visibleTitle, "Preparing…")
        XCTAssertEqual(VoiceStickStatus.searching.visibleTitle, "Searching…")
        XCTAssertEqual(VoiceStickStatus.processing.visibleTitle, "Processing")
        XCTAssertEqual(VoiceStickStatus.disconnected.accessibilityDescription, "设备未连接")
        XCTAssertEqual(VoiceStickStatus.preparing.accessibilityDescription, "正在准备")
        XCTAssertEqual(VoiceStickStatus.searching.accessibilityDescription, "正在搜索 VoiceStick")
        XCTAssertEqual(VoiceStickStatus.processing.accessibilityDescription, "正在处理")
        XCTAssertNotEqual(
            VoiceStickStatus.disconnected.symbolName(hasConnectedDevices: false),
            VoiceStickStatus.processing.symbolName(hasConnectedDevices: false)
        )
        XCTAssertNotEqual(
            VoiceStickStatus.searching.symbolName(hasConnectedDevices: false),
            VoiceStickStatus.ready.symbolName(hasConnectedDevices: true)
        )
    }

    func testInitialUnpairedStateNeedsPairing() {
        XCTAssertEqual(state(paired: []).displayedStatus, .needsPairing)
    }

    func testInitialPairedStateIsDisconnectedNotSearchingOrReady() {
        let current = state()
        XCTAssertEqual(current.displayedStatus, .disconnected)
        XCTAssertNotEqual(current.displayedStatus, .searching)
        XCTAssertNotEqual(current.displayedStatus, .ready)
    }

    func testDescriptiveSearchTextDoesNotClaimThatScanningStarted() {
        var current = state()
        for status in [VoiceStickStatus.searching, .preparing, .ready, .processing] {
            current.setStatus(status)
            XCTAssertEqual(current.displayedStatus, .disconnected)
        }
        current.setPairedDeviceIDs([])
        current.setStatus(.searching)
        XCTAssertEqual(current.displayedStatus, .needsPairing)
    }

    func testConnectionWaitsForTransportReady() {
        var current = state()
        XCTAssertEqual(current.updateConnections(["A"]), [])
        XCTAssertEqual(current.displayedStatus, .preparing)
        current.setStatus(.ready, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .preparing)
        current.markTransportReady("A")
        XCTAssertEqual(current.displayedStatus, .ready)
    }

    func testNewlyPairedConnectionIsNotFilteredByOldPairingSnapshot() {
        var current = state(paired: ["A"])
        current.updateConnections(["A", "B"])
        current.setPairedDeviceIDs(["A", "B"])
        current.markTransportReady("B")
        XCTAssertEqual(current.displayedStatus, .ready)
    }

    func testUnknownTransportReadyIsIgnored() {
        var current = state()
        current.markTransportReady("A")
        XCTAssertEqual(current.displayedStatus, .disconnected)
        current.updateConnections(["A"])
        current.markTransportReady("B")
        XCTAssertEqual(current.displayedStatus, .preparing)
    }

    func testDisconnectClearsTransportReadyAndReconnectMustPrepareAgain() {
        var current = state()
        current.updateConnections(["A"])
        current.markTransportReady("A")
        XCTAssertEqual(current.displayedStatus, .ready)
        XCTAssertEqual(current.updateConnections([]), ["A"])
        XCTAssertEqual(current.displayedStatus, .disconnected)
        current.updateConnections(["A"])
        XCTAssertEqual(current.displayedStatus, .preparing)
    }

    func testOneReadyDeviceKeepsIdlePresentationReadyWhenAnotherConnects() {
        var current = state()
        current.updateConnections(["A"])
        current.markTransportReady("A")
        current.updateConnections(["A", "B"])
        XCTAssertEqual(current.displayedStatus, .ready)
    }

    func testDeviceBConnectionOrReadinessDoesNotOverrideDeviceAProcessing() {
        var current = state()
        current.updateConnections(["A"])
        current.setStatus(.processing, deviceID: "A")
        current.updateConnections(["A", "B"])
        XCTAssertEqual(current.displayedStatus, .processing)
        current.markTransportReady("B")
        XCTAssertEqual(current.displayedStatus, .processing)
        current.setStatus(.preparing, deviceID: "B")
        XCTAssertEqual(current.displayedStatus, .processing)
    }

    func testDeviceADisconnectDoesNotClearDeviceBActivity() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.setStatus(.listening, deviceID: "B")
        XCTAssertEqual(current.updateConnections(["B"]), ["A"])
        XCTAssertEqual(current.displayedStatus, .listening)
    }

    func testDisconnectingMostRecentDeviceRestoresOtherDevicesActivity() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.setStatus(.processing, deviceID: "A")
        current.setStatus(.listening, deviceID: "B")
        XCTAssertEqual(current.displayedStatus, .listening)
        XCTAssertEqual(current.updateConnections(["A"]), ["B"])
        XCTAssertEqual(current.displayedStatus, .processing)
    }

    func testCompletingMostRecentDeviceRestoresOtherDevicesActivity() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.setStatus(.processing, deviceID: "A")
        current.setStatus(.listening, deviceID: "B")
        current.setStatus(.ready, deviceID: "B")
        XCTAssertEqual(current.displayedStatus, .processing)
        current.setStatus(.listening, deviceID: "B")
        current.setStatus(.idle, deviceID: "B")
        XCTAssertEqual(current.displayedStatus, .processing)
    }

    func testTransportReadinessAndNewConnectionKeepParallelActivities() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.setStatus(.processing, deviceID: "A")
        current.setStatus(.listening, deviceID: "B")
        current.markTransportReady("A")
        current.updateConnections(["A", "B", "C"])
        XCTAssertEqual(current.displayedStatus, .listening)
        current.setStatus(.ready, deviceID: "B")
        XCTAssertEqual(current.displayedStatus, .processing)
    }

    func testDisconnectedOwnersActivityIsClearedWithoutMarkingOthersReady() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.setStatus(.processing, deviceID: "A")
        current.updateConnections(["B"])
        XCTAssertEqual(current.displayedStatus, .preparing)
    }

    func testLateDisconnectedDeviceStatusesCannotOverrideConnectedDevice() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.updateConnections(["B"])
        current.setStatus(.processing, deviceID: "B")
        for status in [VoiceStickStatus.listening, .processing, .error, .ready, .idle] {
            current.setStatus(status, deviceID: "A")
            XCTAssertEqual(current.displayedStatus, .processing)
        }
        current.markTransportReady("A")
        XCTAssertEqual(current.displayedStatus, .processing)
        current.setStatus(.idle, deviceID: "B")
        XCTAssertEqual(current.displayedStatus, .preparing)
    }

    func testReadyOrIdleForOneDeviceCannotClearAnotherDevicesActivity() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.setStatus(.processing, deviceID: "B")
        current.setStatus(.ready, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .processing)
        current.setStatus(.idle, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .processing)
        current.setStatus(.idle, deviceID: "B")
        XCTAssertEqual(current.displayedStatus, .preparing)
    }

    func testMatchingOwnersReadyClearsActivityButDoesNotCreateTransportReadiness() {
        var current = state()
        current.updateConnections(["A"])
        current.setStatus(.error, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .error)
        current.setStatus(.ready, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .preparing)
        current.markTransportReady("A")
        current.setStatus(.listening, deviceID: "A")
        current.setStatus(.ready, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .ready)
    }

    func testGlobalActivitySurvivesPartialDisconnectButIsClearedWhenAllDisconnect() {
        var current = state()
        current.updateConnections(["A", "B"])
        current.setStatus(.processing)
        current.updateConnections(["B"])
        XCTAssertEqual(current.displayedStatus, .processing)
        current.updateConnections([])
        XCTAssertEqual(current.displayedStatus, .disconnected)
        current.setStatus(.processing)
        current.setStatus(.error)
        XCTAssertEqual(current.displayedStatus, .disconnected)
        current.updateConnections(["B"])
        XCTAssertEqual(current.displayedStatus, .preparing)
    }

    func testDeviceSpecificIdleCannotClearGlobalActivity() {
        var current = state()
        current.updateConnections(["A"])
        current.setStatus(.listening)
        current.setStatus(.ready, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .listening)
        current.setStatus(.idle, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .listening)
        current.setStatus(.idle)
        XCTAssertEqual(current.displayedStatus, .preparing)
    }

    func testFinishingGlobalActivityDoesNotClearDeviceActivity() {
        var current = state()
        current.updateConnections(["A"])
        current.setStatus(.processing, deviceID: "A")
        current.setStatus(.error)
        XCTAssertEqual(current.displayedStatus, .error)
        current.setStatus(.ready)
        XCTAssertEqual(current.displayedStatus, .processing)
        current.setStatus(.listening)
        current.setStatus(.idle)
        XCTAssertEqual(current.displayedStatus, .processing)
    }

    func testPairingChangesOnlyAffectDisconnectedPresentation() {
        var current = state(paired: [])
        current.setPairedDeviceIDs(["A"])
        XCTAssertEqual(current.displayedStatus, .disconnected)
        current.setPairedDeviceIDs([])
        XCTAssertEqual(current.displayedStatus, .needsPairing)
    }

    func testConnectionHintsCannotReplaceAValidActivity() {
        var current = state()
        current.updateConnections(["A"])
        current.setStatus(.listening, deviceID: "A")
        for status in [VoiceStickStatus.searching, .disconnected, .preparing, .needsPairing] {
            current.setStatus(status)
            XCTAssertEqual(current.displayedStatus, .listening)
        }
    }

    func testPartialTextUsesAnExplicitListeningStatusRatherThanItsContent() {
        var current = state()
        current.updateConnections(["A"])
        let partialText = "这是测试用的部分文本"
        XCTAssertEqual(VoiceStickStatus(text: partialText), .idle)
        current.setStatus(.listening, deviceID: "A")
        XCTAssertEqual(current.displayedStatus, .listening)
        XCTAssertNotEqual(current.displayedStatus, .processing)
    }
}
