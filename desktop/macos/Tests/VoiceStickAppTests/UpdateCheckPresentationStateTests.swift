import XCTest
import Sparkle
@testable import VoiceStickApp

final class UpdateCheckPresentationStateTests: XCTestCase {
    func testIdleCheckShowsFeedbackBeforeSparkleStarts() {
        var state = UpdateCheckPresentationState()
        XCTAssertEqual(state.request(canCheckForUpdates: true, sessionInProgress: false), .showFeedbackAndCheck)
        XCTAssertTrue(state.isWaitingForSparkle)
    }

    func testUnavailableBackgroundCheckDoesNotCreateFeedback() {
        var state = UpdateCheckPresentationState()
        XCTAssertEqual(state.request(canCheckForUpdates: false, sessionInProgress: true), .unavailable)
        XCTAssertFalse(state.isWaitingForSparkle)
    }

    func testUnstartedUpdaterDoesNotCreateFeedback() {
        var state = UpdateCheckPresentationState()
        XCTAssertEqual(state.request(canCheckForUpdates: false, sessionInProgress: false), .unavailable)
        XCTAssertFalse(state.isWaitingForSparkle)
    }

    func testExistingNativeSessionIsFocusedWithoutAnotherCheck() {
        var state = UpdateCheckPresentationState()
        XCTAssertEqual(state.request(canCheckForUpdates: true, sessionInProgress: true), .focusSparkle)
        XCTAssertFalse(state.isWaitingForSparkle)
    }

    func testRepeatedClickBringsFeedbackToFrontWithoutStartingAnotherCheck() {
        var state = UpdateCheckPresentationState()
        _ = state.request(canCheckForUpdates: true, sessionInProgress: false)
        XCTAssertEqual(state.request(canCheckForUpdates: false, sessionInProgress: true), .bringFeedbackToFront)
        XCTAssertTrue(state.isWaitingForSparkle)
    }

    func testInitialAvailableValueDoesNotDismissNewFeedback() {
        var state = UpdateCheckPresentationState()
        _ = state.request(canCheckForUpdates: true, sessionInProgress: false)
        XCTAssertFalse(state.availabilityChanged(canCheckForUpdates: true))
        XCTAssertTrue(state.isWaitingForSparkle)
    }

    func testBusyToAvailableTransitionHandsOffToNativeWindow() {
        var state = UpdateCheckPresentationState()
        _ = state.request(canCheckForUpdates: true, sessionInProgress: false)
        XCTAssertFalse(state.availabilityChanged(canCheckForUpdates: false))
        XCTAssertTrue(state.availabilityChanged(canCheckForUpdates: true))
        XCTAssertFalse(state.isWaitingForSparkle)
        XCTAssertFalse(state.availabilityChanged(canCheckForUpdates: true))
    }

    func testResultErrorOrCancellationFinishesOnlyOnce() {
        var state = UpdateCheckPresentationState()
        _ = state.request(canCheckForUpdates: true, sessionInProgress: false)
        XCTAssertTrue(state.finish())
        XCTAssertFalse(state.finish())
        XCTAssertFalse(state.availabilityChanged(canCheckForUpdates: false))
        XCTAssertFalse(state.availabilityChanged(canCheckForUpdates: true))
    }

    func testNextRequestNeedsItsOwnBusyTransition() {
        var state = UpdateCheckPresentationState()
        _ = state.request(canCheckForUpdates: true, sessionInProgress: false)
        _ = state.availabilityChanged(canCheckForUpdates: false)
        _ = state.finish()
        XCTAssertEqual(state.request(canCheckForUpdates: true, sessionInProgress: false), .showFeedbackAndCheck)
        XCTAssertFalse(state.availabilityChanged(canCheckForUpdates: true))
        XCTAssertTrue(state.isWaitingForSparkle)
    }

    func testModalErrorAndSessionFinishNotifyFeedbackBeforeSparkleUI() {
        let delegate = DevelopmentVersionDisplay()
        var events: [String] = []
        delegate.onWillShowUpdateUI = { events.append("dismiss-feedback") }
        delegate.standardUserDriverWillShowModalAlert()
        delegate.standardUserDriverWillFinishUpdateSession()
        XCTAssertEqual(events, ["dismiss-feedback", "dismiss-feedback"])
        XCTAssertTrue(delegate.responds(to: NSSelectorFromString("standardUserDriverWillShowModalAlert")))
        XCTAssertTrue(delegate.responds(to: NSSelectorFromString("standardUserDriverWillFinishUpdateSession")))
    }

    func testUpdaterLifecycleCallbacksUseSparklesObjectiveCSelectors() {
        let controller = UpdateCheckController()
        for selector in [
            "checkForUpdates:",
            "validateMenuItem:",
            "updater:didFindValidUpdate:",
            "updaterDidNotFindUpdate:error:",
            "updater:didAbortWithError:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:",
        ] {
            XCTAssertTrue(controller.responds(to: NSSelectorFromString(selector)), selector)
        }
        XCTAssertTrue(DevelopmentVersionDisplay().responds(to: NSSelectorFromString(
            "standardUserDriverWillHandleShowingUpdate:forUpdate:state:"
        )))
    }
}
