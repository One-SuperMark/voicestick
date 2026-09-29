import Foundation

struct AppVersion {
    static let current = AppVersion(infoDictionary: Bundle.main.infoDictionary ?? [:])

    let releaseVersion: String
    let developmentVersion: String?

    init(infoDictionary: [String: Any]) {
        releaseVersion = infoDictionary["CFBundleShortVersionString"] as? String ?? "未知"
        guard let buildVersion = infoDictionary["CFBundleVersion"] as? String,
              buildVersion == releaseVersion,
              let localVersion = infoDictionary["VoiceStickDevelopmentVersion"] as? String else {
            developmentVersion = nil
            return
        }

        let components = localVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              components.prefix(3).joined(separator: ".") == releaseVersion,
              let revision = Int(components[3]), revision > 0,
              String(revision) == components[3] else {
            developmentVersion = nil
            return
        }
        developmentVersion = localVersion
    }

    var isDevelopmentBuild: Bool { developmentVersion != nil }

    var displayVersion: String { developmentVersion ?? releaseVersion }

    var displayLabel: String {
        isDevelopmentBuild ? "\(displayVersion)（开发版）" : displayVersion
    }

    func displayLabel(for bundleDisplayVersion: String, bundleVersion: String) -> String {
        guard isDevelopmentBuild,
              bundleDisplayVersion == releaseVersion,
              bundleVersion == releaseVersion else { return bundleDisplayVersion }
        return displayLabel
    }
}
