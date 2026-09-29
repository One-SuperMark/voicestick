import Foundation
import Sparkle

/// Changes presentation only; Sparkle keeps comparing the three-part CFBundleVersion.
final class DevelopmentVersionDisplay: NSObject, SPUStandardUserDriverDelegate, SUVersionDisplay {
    private let version: AppVersion

    init(version: AppVersion = .current) {
        self.version = version
        super.init()
    }

    func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? {
        version.isDevelopmentBuild ? self : nil
    }

    func formatUpdateVersion(
        fromUpdate update: SUAppcastItem,
        andBundleDisplayVersion inOutBundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
        withBundleVersion bundleVersion: String
    ) -> String {
        inOutBundleDisplayVersion.pointee = version.displayLabel(
            for: inOutBundleDisplayVersion.pointee as String,
            bundleVersion: bundleVersion
        ) as NSString
        // Never apply the local development suffix to a remote release.
        return update.displayVersionString
    }

    func formatBundleDisplayVersion(
        _ bundleDisplayVersion: String,
        withBundleVersion bundleVersion: String,
        matchingUpdate: SUAppcastItem?
    ) -> String {
        version.displayLabel(for: bundleDisplayVersion, bundleVersion: bundleVersion)
    }
}
