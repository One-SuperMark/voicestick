import XCTest
import Sparkle
@testable import VoiceStickApp

final class AppVersionTests: XCTestCase {
    private func version(localVersion: String? = nil, buildVersion: String = "0.3.6") -> AppVersion {
        var info: [String: Any] = [
            "CFBundleShortVersionString": "0.3.6",
            "CFBundleVersion": buildVersion,
        ]
        if let localVersion { info["VoiceStickDevelopmentVersion"] = localVersion }
        return AppVersion(infoDictionary: info)
    }

    func testFormalVersionKeepsThreePartsAndDefaultSparkleDisplay() {
        let current = version()
        XCTAssertEqual(current.displayVersion, "0.3.6")
        XCTAssertEqual(current.displayLabel, "0.3.6")
        XCTAssertFalse(current.isDevelopmentBuild)
        XCTAssertNil(DevelopmentVersionDisplay(version: current).standardUserDriverRequestsVersionDisplayer())
    }

    func testLocalVersionShowsFourthPartAndDevelopmentLabel() {
        let current = version(localVersion: "0.3.6.1")
        XCTAssertEqual(current.releaseVersion, "0.3.6")
        XCTAssertEqual(current.displayVersion, "0.3.6.1")
        XCTAssertEqual(current.displayLabel, "0.3.6.1（开发版）")
        XCTAssertNotNil(DevelopmentVersionDisplay(version: current).standardUserDriverRequestsVersionDisplayer())
    }

    func testMultipleDigitDevelopmentRevision() {
        XCTAssertEqual(version(localVersion: "0.3.6.12").displayVersion, "0.3.6.12")
    }

    func testInvalidOrMismatchedDevelopmentMetadataIsIgnored() {
        for value in ["0.3.6", "0.3.7.1", "0.3.6.0", "0.3.6.-1", "0.3.6.01", "0.3.6.a", "0.3.6.1.2", "0.3.6."] {
            XCTAssertEqual(version(localVersion: value).displayVersion, "0.3.6", value)
        }
        XCTAssertEqual(version(localVersion: "0.3.6.1", buildVersion: "0.3.7").displayVersion, "0.3.6")
    }

    func testLatestVersionWindowUsesLocalDisplayEvenWithoutMatchingItem() {
        let formatter = DevelopmentVersionDisplay(version: version(localVersion: "0.3.6.1"))
        XCTAssertEqual(
            formatter.formatBundleDisplayVersion("0.3.6", withBundleVersion: "0.3.6", matchingUpdate: nil),
            "0.3.6.1（开发版）"
        )
        XCTAssertTrue(formatter.responds(to: NSSelectorFromString("formatBundleDisplayVersion:withBundleVersion:matchingUpdate:")))
    }

    func testFormatterDoesNotRelabelAnotherBundleVersion() {
        let formatter = DevelopmentVersionDisplay(version: version(localVersion: "0.3.6.1"))
        XCTAssertEqual(
            formatter.formatBundleDisplayVersion("0.3.7", withBundleVersion: "0.3.7", matchingUpdate: nil),
            "0.3.7"
        )
    }

    func testRemoteReleaseIsNotGivenLocalSuffix() throws {
        let item = try XCTUnwrap(SUAppcastItem(dictionary: [
            "enclosure": [
                "url": "https://example.com/VoiceStick-0.3.7.dmg",
                "sparkle:version": "0.3.7",
                "sparkle:shortVersionString": "0.3.7",
                "length": "1",
                "type": "application/octet-stream",
            ],
        ]))
        let formatter = DevelopmentVersionDisplay(version: version(localVersion: "0.3.6.1"))
        var hostVersion: NSString = "0.3.6"
        let updateVersion = formatter.formatUpdateVersion(
            fromUpdate: item,
            andBundleDisplayVersion: &hostVersion,
            withBundleVersion: "0.3.6"
        )
        XCTAssertEqual(updateVersion, "0.3.7")
        XCTAssertEqual(hostVersion as String, "0.3.6.1（开发版）")
    }

    func testDevelopmentDisplayDoesNotChangeOfficialUpdateOrdering() {
        let current = version(localVersion: "0.3.6.1")
        let comparator = SUStandardVersionComparator.default
        XCTAssertEqual(comparator.compareVersion(current.releaseVersion, toVersion: "0.3.6"), .orderedSame)
        XCTAssertEqual(comparator.compareVersion(current.releaseVersion, toVersion: "0.3.7"), .orderedAscending)
    }
}
