/// Tracks only the short gap before Sparkle can present its own update UI.
/// Background sessions must never create a second, user-initiated check.
struct UpdateCheckPresentationState {
    enum Action: Equatable {
        case unavailable
        case showFeedbackAndCheck
        case bringFeedbackToFront
        case focusSparkle
    }

    private(set) var isWaitingForSparkle = false
    private var observedBusyTransition = false

    mutating func request(canCheckForUpdates: Bool, sessionInProgress: Bool) -> Action {
        if isWaitingForSparkle { return .bringFeedbackToFront }
        guard canCheckForUpdates else { return .unavailable }
        guard !sessionInProgress else { return .focusSparkle }
        isWaitingForSparkle = true
        observedBusyTransition = false
        return .showFeedbackAndCheck
    }

    mutating func availabilityChanged(canCheckForUpdates: Bool) -> Bool {
        guard isWaitingForSparkle else { return false }
        if !canCheckForUpdates {
            observedBusyTransition = true
            return false
        }
        // Sparkle 2.9.1 re-enables its check action immediately before showing
        // the native checking window (or when an aborted session finishes).
        guard observedBusyTransition else { return false }
        return finish()
    }

    @discardableResult
    mutating func finish() -> Bool {
        let wasWaiting = isWaitingForSparkle
        isWaitingForSparkle = false
        observedBusyTransition = false
        return wasWaiting
    }
}
