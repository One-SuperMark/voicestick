import AppKit
import Sparkle

/// Gives menu clicks immediate feedback while Sparkle probes its installer.
/// Sparkle still owns the network request, cancellation, results and installation.
final class UpdateCheckController: NSObject, NSMenuItemValidation, SPUUpdaterDelegate {
    private weak var updaterController: SPUStandardUpdaterController?
    private var availabilityObservation: NSKeyValueObservation?
    private var presentationState = UpdateCheckPresentationState()
    private var windowController: NSWindowController?
    private var progressIndicator: NSProgressIndicator?

    func bind(to controller: SPUStandardUpdaterController) {
        updaterController = controller
        availabilityObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, change in
            guard let self else { return }
            let available = change.newValue ?? updater.canCheckForUpdates
            // SPUUpdater and its KVO notifications run on the main thread.
            if self.presentationState.availabilityChanged(canCheckForUpdates: available) {
                self.hideFeedbackWindow()
            }
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let updaterController else { return }
        let updater = updaterController.updater
        switch presentationState.request(
            canCheckForUpdates: updater.canCheckForUpdates,
            sessionInProgress: updater.sessionInProgress
        ) {
        case .unavailable:
            return
        case .bringFeedbackToFront:
            showFeedbackWindow()
        case .focusSparkle:
            updaterController.checkForUpdates(sender)
        case .showFeedbackAndCheck:
            // Display and flush the window before starting Sparkle's async probe.
            showFeedbackWindow()
            updaterController.checkForUpdates(sender)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return updaterController?.updater.canCheckForUpdates ?? false
    }

    func finishFeedback() {
        guard presentationState.finish() else { return }
        hideFeedbackWindow()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        finishFeedback()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        finishFeedback()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        finishFeedback()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        finishFeedback()
    }

    private func showFeedbackWindow() {
        if windowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 330, height: 130),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceStick · 检查更新"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]

            let progress = NSProgressIndicator()
            progress.style = .spinning
            progress.controlSize = .regular
            progress.isIndeterminate = true
            progress.setAccessibilityLabel("正在检查更新")
            progressIndicator = progress

            let label = NSTextField(labelWithString: "正在检查更新…")
            label.font = .systemFont(ofSize: 16, weight: .medium)
            let stack = NSStackView(views: [progress, label])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            if let contentView = window.contentView {
                contentView.addSubview(stack)
                NSLayoutConstraint.activate([
                    progress.widthAnchor.constraint(equalToConstant: 24),
                    progress.heightAnchor.constraint(equalToConstant: 24),
                    stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                    stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                ])
            }
            window.center()
            windowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        progressIndicator?.startAnimation(nil)
        windowController?.window?.displayIfNeeded()
    }

    private func hideFeedbackWindow() {
        progressIndicator?.stopAnimation(nil)
        windowController?.window?.orderOut(nil)
    }
}
