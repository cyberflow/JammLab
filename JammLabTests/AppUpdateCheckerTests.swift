import Foundation
import XCTest
@testable import JammLab

final class AppVersionTests: XCTestCase {
    func testStableVersionsUseNumericComparison() throws {
        let older = try XCTUnwrap(AppVersion(stableVersionString: "1.9.0"))
        let newer = try XCTUnwrap(AppVersion(stableVersionString: "1.10.0"))

        XCTAssertLessThan(older, newer)
        XCTAssertEqual(newer.description, "1.10.0")
    }

    func testStableVersionAcceptsLeadingV() throws {
        XCTAssertEqual(
            AppVersion(stableVersionString: "v2.3.4"),
            AppVersion(stableVersionString: "2.3.4")
        )
    }

    func testStableVersionRequiresExactlyThreeNumericComponents() {
        XCTAssertNil(AppVersion(stableVersionString: "1"))
        XCTAssertNil(AppVersion(stableVersionString: "1.0"))
        XCTAssertNil(AppVersion(stableVersionString: "1.0.0.1"))
        XCTAssertNil(AppVersion(stableVersionString: "1.0.x"))
        XCTAssertNil(AppVersion(stableVersionString: "1.0.0-beta"))
        XCTAssertNil(AppVersion(stableVersionString: "1.0.0-dev.1"))
    }

    func testBuildMetadataRequiresStableBuildFlagAndVersion() {
        XCTAssertTrue(
            AppBuildMetadata(
                versionString: "1.2.3",
                isStableReleaseBuild: true
            ).isStableRelease
        )
        XCTAssertFalse(
            AppBuildMetadata(
                versionString: "1.2.3",
                isStableReleaseBuild: false
            ).isStableRelease
        )
        XCTAssertFalse(
            AppBuildMetadata(
                versionString: "1.2",
                isStableReleaseBuild: true
            ).isStableRelease
        )
    }

    func testCompiledReleasePolicyMatchesBuildFlags() {
        let metadata = AppBuildMetadata(
            versionString: "1.2.3",
            isStableReleaseBuild: AppBuildMetadata.compiledIsStableReleaseBuild
        )

#if JAMMLAB_STABLE_RELEASE
        XCTAssertTrue(metadata.isStableRelease)
#if DEBUG
        XCTAssertFalse(AppUpdateRuntimePolicy.automaticChecksEnabled(for: metadata))
#else
        XCTAssertTrue(AppUpdateRuntimePolicy.automaticChecksEnabled(for: metadata))
#endif
#else
        XCTAssertFalse(metadata.isStableRelease)
        XCTAssertFalse(AppUpdateRuntimePolicy.automaticChecksEnabled(for: metadata))
#endif
    }

    func testReleaseNotesFormatterRemovesMarkdownLinks() {
        let attributed = AppReleaseNotesFormatter.nonInteractiveMarkdown(
            "Read [release details](https://example.com) for **more**."
        )

        XCTAssertFalse(attributed.runs.contains { $0.link != nil })
        XCTAssertTrue(String(attributed.characters).contains("release details"))
    }
}

final class GitHubLatestReleaseClientTests: XCTestCase {
    func testRequestTargetsLatestReleaseWithRequiredHeadersAndTimeout() throws {
        let currentVersion = try XCTUnwrap(AppVersion(stableVersionString: "1.2.3"))
        let client = GitHubLatestReleaseClient()

        let request = client.makeRequest(currentVersion: currentVersion)

        XCTAssertEqual(request.url, GitHubLatestReleaseClient.endpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, GitHubLatestReleaseClient.timeout)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-GitHub-Api-Version"),
            GitHubLatestReleaseClient.apiVersion
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "JammLab/1.2.3")
    }

    func testClientDecodesStableRelease() async throws {
        let loader = StubHTTPDataLoader(
            data: releaseJSON(
                tag: "v1.3.0",
                name: "JammLab 1.3",
                body: "Release notes",
                htmlURL: "https://github.com/cyberflow/JammLab/releases/tag/v1.3.0"
            ),
            statusCode: 200
        )
        let client = GitHubLatestReleaseClient(dataLoader: loader)
        let currentVersion = try XCTUnwrap(AppVersion(stableVersionString: "1.2.3"))

        let release = try await client.fetchLatestRelease(currentVersion: currentVersion)

        XCTAssertEqual(release.version.description, "1.3.0")
        XCTAssertEqual(release.title, "JammLab 1.3")
        XCTAssertEqual(release.notes, "Release notes")
        XCTAssertEqual(
            release.pageURL.absoluteString,
            "https://github.com/cyberflow/JammLab/releases/tag/v1.3.0"
        )
    }

    func testClientFallsBackWhenOptionalTextIsMissing() async throws {
        let loader = StubHTTPDataLoader(
            data: releaseJSON(
                tag: "v1.3.0",
                name: nil,
                body: nil,
                htmlURL: "https://github.com/cyberflow/JammLab/releases/tag/v1.3.0"
            ),
            statusCode: 200
        )
        let client = GitHubLatestReleaseClient(dataLoader: loader)
        let currentVersion = try XCTUnwrap(AppVersion(stableVersionString: "1.2.3"))

        let release = try await client.fetchLatestRelease(currentVersion: currentVersion)

        XCTAssertEqual(release.title, "JammLab 1.3.0")
        XCTAssertEqual(release.notes, "")
    }

    func testClientRejectsUnsuccessfulStatus() async throws {
        let loader = StubHTTPDataLoader(data: Data(), statusCode: 403)
        let client = GitHubLatestReleaseClient(dataLoader: loader)
        let currentVersion = try XCTUnwrap(AppVersion(stableVersionString: "1.2.3"))

        do {
            _ = try await client.fetchLatestRelease(currentVersion: currentVersion)
            XCTFail("Expected an HTTP status error")
        } catch let error as GitHubLatestReleaseError {
            guard case .unsuccessfulStatus(403) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testClientRejectsDraftPrereleaseAndSuffixedTags() async throws {
        let currentVersion = try XCTUnwrap(AppVersion(stableVersionString: "1.2.3"))
        let payloads = [
            releaseJSON(
                tag: "v1.3.0",
                htmlURL: "https://github.com/cyberflow/JammLab/releases/tag/v1.3.0",
                draft: true
            ),
            releaseJSON(
                tag: "v1.3.0",
                htmlURL: "https://github.com/cyberflow/JammLab/releases/tag/v1.3.0",
                prerelease: true
            ),
            releaseJSON(
                tag: "v1.3.0-beta",
                htmlURL: "https://github.com/cyberflow/JammLab/releases/tag/v1.3.0-beta"
            )
        ]

        for payload in payloads {
            let client = GitHubLatestReleaseClient(
                dataLoader: StubHTTPDataLoader(data: payload, statusCode: 200)
            )

            do {
                _ = try await client.fetchLatestRelease(currentVersion: currentVersion)
                XCTFail("Expected an unsupported release error")
            } catch let error as GitHubLatestReleaseError {
                guard case .unsupportedRelease = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testClientRejectsUntrustedReleaseURL() async throws {
        let loader = StubHTTPDataLoader(
            data: releaseJSON(
                tag: "v1.3.0",
                htmlURL: "https://example.com/cyberflow/JammLab/releases/tag/v1.3.0"
            ),
            statusCode: 200
        )
        let client = GitHubLatestReleaseClient(dataLoader: loader)
        let currentVersion = try XCTUnwrap(AppVersion(stableVersionString: "1.2.3"))

        do {
            _ = try await client.fetchLatestRelease(currentVersion: currentVersion)
            XCTFail("Expected an invalid release URL error")
        } catch let error as GitHubLatestReleaseError {
            guard case .invalidReleaseURL = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testTrustedReleaseURLValidation() {
        XCTAssertTrue(
            GitHubLatestReleaseClient.isTrustedReleaseURL(
                URL(string: "https://github.com/cyberflow/JammLab/releases/tag/v1.2.3")!
            )
        )
        XCTAssertFalse(
            GitHubLatestReleaseClient.isTrustedReleaseURL(
                URL(string: "http://github.com/cyberflow/JammLab/releases/tag/v1.2.3")!
            )
        )
        XCTAssertFalse(
            GitHubLatestReleaseClient.isTrustedReleaseURL(
                URL(string: "https://example.com/cyberflow/JammLab/releases/tag/v1.2.3")!
            )
        )
        XCTAssertFalse(
            GitHubLatestReleaseClient.isTrustedReleaseURL(
                URL(string: "https://github.com/another/project/releases/tag/v1.2.3")!
            )
        )
    }

    private func releaseJSON(
        tag: String,
        name: String? = "JammLab",
        body: String? = "Notes",
        htmlURL: String,
        draft: Bool = false,
        prerelease: Bool = false
    ) -> Data {
        var payload: [String: Any] = [
            "tag_name": tag,
            "html_url": htmlURL,
            "draft": draft,
            "prerelease": prerelease
        ]
        if let name {
            payload["name"] = name
        }
        if let body {
            payload["body"] = body
        }
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}

@MainActor
final class AppUpdateCoordinatorTests: XCTestCase {
    func testDisabledCheckDoesNotCallProvider() async throws {
        let provider = StubLatestReleaseProvider(release: try release("1.3.0"))
        let coordinator = AppUpdateCoordinator(
            releaseProvider: provider,
            currentVersion: try version("1.2.3"),
            defaults: try temporaryUserDefaults(),
            checksEnabled: false
        )

        let result = await coordinator.checkAtLaunch()
        let invocationCount = await provider.count()

        XCTAssertNil(result)
        XCTAssertEqual(invocationCount, 0)
    }

    func testLaunchCheckRunsOnlyOnce() async throws {
        let provider = StubLatestReleaseProvider(release: try release("1.3.0"))
        let coordinator = AppUpdateCoordinator(
            releaseProvider: provider,
            currentVersion: try version("1.2.3"),
            defaults: try temporaryUserDefaults(),
            checksEnabled: true
        )

        let firstResult = await coordinator.checkAtLaunch()
        let secondResult = await coordinator.checkAtLaunch()
        let invocationCount = await provider.count()

        XCTAssertNotNil(firstResult)
        XCTAssertNil(secondResult)
        XCTAssertEqual(invocationCount, 1)
    }

    func testConcurrentLaunchChecksRequestOnceAndReturnOneRelease() async throws {
        let targetRelease = try release("1.3.0")
        let provider = GatedLatestReleaseProvider(release: targetRelease)
        let coordinator = AppUpdateCoordinator(
            releaseProvider: provider,
            currentVersion: try version("1.2.3"),
            defaults: try temporaryUserDefaults(),
            checksEnabled: true
        )

        async let firstResult = coordinator.checkAtLaunch()
        await provider.waitUntilRequestStarts()
        async let secondResult = coordinator.checkAtLaunch()
        await provider.resume()

        let results = await [firstResult, secondResult]
        let invocationCount = await provider.count()

        XCTAssertEqual(results.compactMap { $0 }, [targetRelease])
        XCTAssertEqual(invocationCount, 1)
    }

    func testNewerReleaseIsPresentedButEqualOrOlderReleaseIsNot() async throws {
        let currentVersion = try version("1.2.3")

        for (latestVersion, shouldPresent) in [
            ("1.3.0", true),
            ("1.2.3", false),
            ("1.2.2", false)
        ] {
            let provider = StubLatestReleaseProvider(release: try release(latestVersion))
            let coordinator = AppUpdateCoordinator(
                releaseProvider: provider,
                currentVersion: currentVersion,
                defaults: try temporaryUserDefaults(),
                checksEnabled: true
            )

            let result = await coordinator.checkAtLaunch()
            XCTAssertEqual(result != nil, shouldPresent, "Latest version: \(latestVersion)")
        }
    }

    func testProviderFailureIsSilent() async throws {
        let provider = StubLatestReleaseProvider(shouldFail: true)
        let coordinator = AppUpdateCoordinator(
            releaseProvider: provider,
            currentVersion: try version("1.2.3"),
            defaults: try temporaryUserDefaults(),
            checksEnabled: true
        )

        let result = await coordinator.checkAtLaunch()

        XCTAssertNil(result)
    }

    func testSkippedReleaseIsSuppressed() async throws {
        let defaults = try temporaryUserDefaults()
        defaults.set("1.3.0", forKey: AppUpdateCoordinator.skippedVersionDefaultsKey)
        let provider = StubLatestReleaseProvider(release: try release("1.3.0"))
        let coordinator = AppUpdateCoordinator(
            releaseProvider: provider,
            currentVersion: try version("1.2.3"),
            defaults: defaults,
            checksEnabled: true
        )

        let result = await coordinator.checkAtLaunch()

        XCTAssertNil(result)
    }

    func testNewerReleaseClearsStaleSkipAndIsPresented() async throws {
        let defaults = try temporaryUserDefaults()
        defaults.set("1.3.0", forKey: AppUpdateCoordinator.skippedVersionDefaultsKey)
        let provider = StubLatestReleaseProvider(release: try release("1.4.0"))
        let coordinator = AppUpdateCoordinator(
            releaseProvider: provider,
            currentVersion: try version("1.2.3"),
            defaults: defaults,
            checksEnabled: true
        )

        let result = await coordinator.checkAtLaunch()

        XCTAssertEqual(result?.version, try version("1.4.0"))
        XCTAssertNil(defaults.string(forKey: AppUpdateCoordinator.skippedVersionDefaultsKey))
    }

    func testSkipTogglePersistsAndRemovesExactRelease() async throws {
        let defaults = try temporaryUserDefaults()
        let targetRelease = try release("1.3.0")
        let coordinator = AppUpdateCoordinator(
            releaseProvider: StubLatestReleaseProvider(release: targetRelease),
            currentVersion: try version("1.2.3"),
            defaults: defaults,
            checksEnabled: true
        )

        coordinator.setSkipping(true, release: targetRelease)
        XCTAssertTrue(coordinator.isSkipping(targetRelease))
        XCTAssertEqual(
            defaults.string(forKey: AppUpdateCoordinator.skippedVersionDefaultsKey),
            "1.3.0"
        )

        coordinator.setSkipping(false, release: try release("1.4.0"))
        XCTAssertTrue(coordinator.isSkipping(targetRelease))
        XCTAssertEqual(
            defaults.string(forKey: AppUpdateCoordinator.skippedVersionDefaultsKey),
            "1.3.0"
        )

        coordinator.setSkipping(false, release: targetRelease)
        XCTAssertFalse(coordinator.isSkipping(targetRelease))
        XCTAssertNil(defaults.string(forKey: AppUpdateCoordinator.skippedVersionDefaultsKey))
    }

    func testRemindLaterBehaviorPresentsAgainWithNewCoordinator() async throws {
        let defaults = try temporaryUserDefaults()
        let targetRelease = try release("1.3.0")

        let firstCoordinator = AppUpdateCoordinator(
            releaseProvider: StubLatestReleaseProvider(release: targetRelease),
            currentVersion: try version("1.2.3"),
            defaults: defaults,
            checksEnabled: true
        )
        let firstResult = await firstCoordinator.checkAtLaunch()
        XCTAssertNotNil(firstResult)
        XCTAssertNil(defaults.string(forKey: AppUpdateCoordinator.skippedVersionDefaultsKey))

        let nextLaunchCoordinator = AppUpdateCoordinator(
            releaseProvider: StubLatestReleaseProvider(release: targetRelease),
            currentVersion: try version("1.2.3"),
            defaults: defaults,
            checksEnabled: true
        )
        let nextLaunchResult = await nextLaunchCoordinator.checkAtLaunch()
        XCTAssertNotNil(nextLaunchResult)
    }

    private func version(_ value: String) throws -> AppVersion {
        try XCTUnwrap(AppVersion(stableVersionString: value))
    }

    private func release(_ value: String) throws -> AppRelease {
        let version = try version(value)
        return AppRelease(
            version: version,
            title: "JammLab \(value)",
            notes: "Notes",
            pageURL: URL(string: "https://github.com/cyberflow/JammLab/releases/tag/v\(value)")!
        )
    }
}

private actor StubHTTPDataLoader: HTTPDataLoading {
    let data: Data
    let response: URLResponse

    init(data: Data, statusCode: Int) {
        self.data = data
        response = HTTPURLResponse(
            url: GitHubLatestReleaseClient.endpoint,
            statusCode: statusCode,
            httpVersion: "HTTP/2",
            headerFields: nil
        )!
    }

    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        (data, response)
    }
}

private actor StubLatestReleaseProvider: LatestReleaseProviding {
    let release: AppRelease?
    let shouldFail: Bool
    private(set) var invocationCount = 0

    init(release: AppRelease? = nil, shouldFail: Bool = false) {
        self.release = release
        self.shouldFail = shouldFail
    }

    func fetchLatestRelease(currentVersion: AppVersion) async throws -> AppRelease {
        invocationCount += 1
        if shouldFail {
            throw StubError.failed
        }
        return try XCTUnwrap(release)
    }

    func count() -> Int {
        invocationCount
    }

    enum StubError: Error {
        case failed
    }
}

private actor GatedLatestReleaseProvider: LatestReleaseProviding {
    let release: AppRelease
    private var invocationCount = 0
    private var requestStarted = false
    private var requestStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestContinuation: CheckedContinuation<Void, Never>?

    init(release: AppRelease) {
        self.release = release
    }

    func fetchLatestRelease(currentVersion: AppVersion) async throws -> AppRelease {
        invocationCount += 1
        requestStarted = true
        requestStartWaiters.forEach { $0.resume() }
        requestStartWaiters.removeAll()

        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
        return release
    }

    func waitUntilRequestStarts() async {
        guard !requestStarted else { return }
        await withCheckedContinuation { continuation in
            requestStartWaiters.append(continuation)
        }
    }

    func resume() {
        requestContinuation?.resume()
        requestContinuation = nil
    }

    func count() -> Int {
        invocationCount
    }
}
