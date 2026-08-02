import Foundation

struct AppVersion: Comparable, Hashable, Identifiable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    var id: String { description }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    init?(stableVersionString rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionValue = trimmedValue.hasPrefix("v")
            ? String(trimmedValue.dropFirst())
            : trimmedValue
        let components = versionValue.split(separator: ".", omittingEmptySubsequences: false)

        guard
            components.count == 3,
            components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            let major = Int(components[0]),
            let minor = Int(components[1]),
            let patch = Int(components[2])
        else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AppRelease: Equatable, Identifiable, Sendable {
    let version: AppVersion
    let title: String
    let notes: String
    let pageURL: URL

    var id: AppVersion { version }
}

struct AppBuildMetadata: Equatable, Sendable {
    let version: AppVersion?
    let isStableReleaseBuild: Bool

    var isStableRelease: Bool {
        version != nil && isStableReleaseBuild
    }

    init(versionString: String?, isStableReleaseBuild: Bool) {
        version = versionString.flatMap(AppVersion.init(stableVersionString:))
        self.isStableReleaseBuild = isStableReleaseBuild
    }

    init(bundle: Bundle = .main) {
        self.init(
            versionString: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            isStableReleaseBuild: Self.compiledIsStableReleaseBuild
        )
    }

    static var compiledIsStableReleaseBuild: Bool {
#if JAMMLAB_STABLE_RELEASE
        true
#else
        false
#endif
    }
}

enum AppUpdateRuntimePolicy {
    static func automaticChecksEnabled(for metadata: AppBuildMetadata) -> Bool {
#if DEBUG
        false
#else
        metadata.isStableRelease
#endif
    }
}
