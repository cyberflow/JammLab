import Combine
import Foundation
import OSLog

@MainActor
final class AppUpdateCoordinator: ObservableObject {
    static let skippedVersionDefaultsKey = "updates.skippedVersion"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cyberflow.JammLab",
        category: "AppUpdate"
    )

    let currentVersion: AppVersion?

    private let releaseProvider: LatestReleaseProviding
    private let defaults: UserDefaults
    private let checksEnabled: Bool
    private var didAttemptLaunchCheck = false

    init(
        releaseProvider: LatestReleaseProviding,
        currentVersion: AppVersion?,
        defaults: UserDefaults = .standard,
        checksEnabled: Bool
    ) {
        self.releaseProvider = releaseProvider
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.checksEnabled = checksEnabled
    }

    static func live(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) -> AppUpdateCoordinator {
        let metadata = AppBuildMetadata(bundle: bundle)
        return AppUpdateCoordinator(
            releaseProvider: GitHubLatestReleaseClient(),
            currentVersion: metadata.version,
            defaults: defaults,
            checksEnabled: AppUpdateRuntimePolicy.automaticChecksEnabled(for: metadata)
        )
    }

    func checkAtLaunch() async -> AppRelease? {
        guard !didAttemptLaunchCheck else { return nil }
        didAttemptLaunchCheck = true

        guard checksEnabled, let currentVersion else { return nil }

        do {
            let release = try await releaseProvider.fetchLatestRelease(currentVersion: currentVersion)
            let skippedVersion = storedSkippedVersion()

            if let skippedVersion, skippedVersion < release.version {
                defaults.removeObject(forKey: Self.skippedVersionDefaultsKey)
            }

            guard
                release.version > currentVersion,
                skippedVersion != release.version
            else {
                return nil
            }

            return release
        } catch {
            Self.logger.debug(
                "Automatic update check failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    func isSkipping(_ release: AppRelease) -> Bool {
        storedSkippedVersion() == release.version
    }

    func setSkipping(_ shouldSkip: Bool, release: AppRelease) {
        if shouldSkip {
            defaults.set(release.version.description, forKey: Self.skippedVersionDefaultsKey)
        } else if storedSkippedVersion() == release.version {
            defaults.removeObject(forKey: Self.skippedVersionDefaultsKey)
        }
    }

    private func storedSkippedVersion() -> AppVersion? {
        defaults.string(forKey: Self.skippedVersionDefaultsKey)
            .flatMap(AppVersion.init(stableVersionString:))
    }
}
