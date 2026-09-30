import Foundation

/// AppKit coordinates: the guide overlaps only the bottom 30 pt of Settings.
enum AccessibilityGuidePlacement {
    static let arrowCenterX: CGFloat = 48
    static let permissionIconInset: CGFloat = 41
    static let overlap: CGFloat = 30

    static func frame(
        settingsFrame: CGRect?, visibleFrame: CGRect, sidebarWidth: CGFloat = 232, height: CGFloat = 150
    ) -> CGRect {
        let margin: CGFloat = 12
        let preferredWidth = min(560, max(320, (settingsFrame ?? visibleFrame).width - 32))
        let availableWidth = max(0, visibleFrame.width - 2 * margin)
        var width = min(preferredWidth, availableWidth)
        let desiredX: CGFloat
        let desiredY: CGFloat
        if let settingsFrame {
            // Align to the permission-list icons, not the center of the entire window.
            desiredX = settingsFrame.minX + sidebarWidth + permissionIconInset - arrowCenterX
            desiredY = settingsFrame.minY + overlap - height
            let roomOnRight = visibleFrame.maxX - margin - desiredX
            width = min(width, max(min(320, availableWidth), roomOnRight))
        } else {
            desiredX = visibleFrame.midX - width / 2
            desiredY = visibleFrame.minY + margin
        }
        let x = min(max(desiredX, visibleFrame.minX + margin), visibleFrame.maxX - width - margin)
        let y = min(max(desiredY, visibleFrame.minY + margin), visibleFrame.maxY - height - margin)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
