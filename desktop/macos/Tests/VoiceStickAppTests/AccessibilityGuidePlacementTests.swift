import XCTest
@testable import VoiceStickApp

final class AccessibilityGuidePlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testArrowAlignsToPermissionIconColumnAndOverlapsOnly30Points() {
        let settings = CGRect(x: 0, y: 300, width: 740, height: 625)
        let guide = AccessibilityGuidePlacement.frame(settingsFrame: settings, visibleFrame: screen)
        XCTAssertEqual(guide.minX + AccessibilityGuidePlacement.arrowCenterX, 273)
        XCTAssertEqual(guide.maxY - settings.minY, 30)
        XCTAssertEqual(guide.size, CGSize(width: 560, height: 150))
    }

    func testMovedWindowAndDifferentSidebarKeepAlignment() {
        let settings = CGRect(x: 300, y: 220, width: 800, height: 625)
        let guide = AccessibilityGuidePlacement.frame(settingsFrame: settings, visibleFrame: screen, sidebarWidth: 260)
        XCTAssertEqual(guide.minX + AccessibilityGuidePlacement.arrowCenterX, 601)
        XCTAssertEqual(guide.maxY, 250)
    }

    func testCompactAuthorizedPanelPreservesArrowColumnAndTopOverlap() {
        let settings = CGRect(x: 0, y: 300, width: 740, height: 625)
        let guide = AccessibilityGuidePlacement.frame(settingsFrame: settings, visibleFrame: screen, height: 124)
        XCTAssertEqual(guide.minX + AccessibilityGuidePlacement.arrowCenterX, 273)
        XCTAssertEqual(guide.maxY - settings.minY, 30)
        XCTAssertEqual(guide.height, 124)
    }

    func testRightScreenEdgeShrinksPanelBeforeBreakingIconAlignment() {
        let settings = CGRect(x: 700, y: 300, width: 740, height: 625)
        let guide = AccessibilityGuidePlacement.frame(settingsFrame: settings, visibleFrame: screen)
        XCTAssertEqual(guide.minX + AccessibilityGuidePlacement.arrowCenterX, 973)
        XCTAssertEqual(guide.maxX, screen.maxX - 12)
        XCTAssertEqual(guide.width, 503)
    }

    func testBottomScreenEdgeKeepsEntirePanelVisible() {
        let settings = CGRect(x: 0, y: 50, width: 740, height: 625)
        let guide = AccessibilityGuidePlacement.frame(settingsFrame: settings, visibleFrame: screen)
        XCTAssertEqual(guide.minY, 12)
        XCTAssertTrue(screen.contains(guide))
    }

    func testSecondaryScreenWithNegativeOriginUsesGlobalCoordinates() {
        let secondary = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        let settings = CGRect(x: -1300, y: -600, width: 740, height: 625)
        let guide = AccessibilityGuidePlacement.frame(settingsFrame: settings, visibleFrame: secondary)
        XCTAssertEqual(guide.minX + AccessibilityGuidePlacement.arrowCenterX, -1027)
        XCTAssertEqual(guide.maxY, -570)
        XCTAssertTrue(secondary.contains(guide))
    }

    func testMissingSettingsWindowFallsBackToVisibleScreenBottom() {
        let guide = AccessibilityGuidePlacement.frame(settingsFrame: nil, visibleFrame: screen)
        XCTAssertEqual(guide.midX, screen.midX)
        XCTAssertEqual(guide.minY, 12)
        XCTAssertTrue(screen.contains(guide))
    }
}
