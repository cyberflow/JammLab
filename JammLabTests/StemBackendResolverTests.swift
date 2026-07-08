import XCTest
@testable import JammLab

final class StemBackendResolverTests: XCTestCase {
    func testStemBackendResolverUsesBundledSeparatorOnly() throws {
        let resolver = StemBackendResolver(
            helperExecutableURL: URL(fileURLWithPath: "/App/JammLab.app/Contents/Resources/JammLabSeparatorHelper/JammLabSeparatorHelper")
        )

        let commands = resolver.bundledSeparatorCandidates.map { $0.commandDescription(extraArguments: ["--env_info"]) }

        XCTAssertEqual(commands, ["/App/JammLab.app/Contents/Resources/JammLabSeparatorHelper/JammLabSeparatorHelper --env_info"])
        XCTAssertFalse(commands.contains { $0.contains("/usr/bin/env") })
        XCTAssertFalse(commands.contains { $0.contains("/opt/homebrew") })
        XCTAssertFalse(commands.contains { $0.contains("demucs") })
    }

    func testBundledSeparatorDefaultPathResolvesBesideStemHelper() {
        let currentExecutable = URL(fileURLWithPath: "/App/JammLab.app/Contents/Helpers/JammLabStemHelper")
        let helperURL = StemBackendResolver.defaultBundledSeparatorExecutableURL(currentExecutableURL: currentExecutable)

        XCTAssertEqual(
            helperURL.path,
            "/App/JammLab.app/Contents/Resources/JammLabSeparatorHelper/JammLabSeparatorHelper"
        )
    }

    func testStemBackendResolverBuildsBundledSeparationCommand() {
        let candidate = StemBackendCandidate(
            executableURL: URL(fileURLWithPath: "/App/Helpers/JammLabSeparatorHelper/JammLabSeparatorHelper"),
            argumentsPrefix: [],
            displayName: "JammLabSeparatorHelper/1"
        )
        let command = candidate.commandDescription(extraArguments: [
            "/tmp/song.mp3",
            "-m",
            "htdemucs.yaml",
            "--output_format",
            "WAV"
        ])

        XCTAssertEqual(command, "/App/Helpers/JammLabSeparatorHelper/JammLabSeparatorHelper /tmp/song.mp3 -m htdemucs.yaml --output_format WAV")
    }

    func testStemBackendComputeModeHelperArguments() {
        XCTAssertEqual(StemBackendComputeMode.cpuOnly.helperArgument, "cpu")
        XCTAssertEqual(StemBackendComputeMode.auto.helperArgument, "auto")
    }
}
