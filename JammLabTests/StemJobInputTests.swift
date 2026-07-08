import XCTest
@testable import JammLab

final class StemJobInputTests: XCTestCase {
    func testStemJobInputUsesDirectOriginalPathWhenNotSandboxed() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = try temporaryFile(in: directory, name: "song.mp3", contents: "audio")
        let service = StemSeparationService(
            appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false },
            applicationSupportDirectory: directory.appendingPathComponent("support", isDirectory: true)
        )

        let input = try service.jobInput(
            for: audioURL,
            jobDirectory: directory.appendingPathComponent("job", isDirectory: true),
            mode: StemJobInputMode.direct
        )

        XCTAssertEqual(input.audioPath, audioURL.path)
        XCTAssertNil(input.stagedInputDirectory)
    }

    func testStemJobInputStagesAudioInsideJobDirectoryWhenSandboxed() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = try temporaryFile(in: directory, name: "song.mp3", contents: "audio")
        let jobDirectory = directory.appendingPathComponent("job", isDirectory: true)
        let service = StemSeparationService(
            appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { true },
            applicationSupportDirectory: directory.appendingPathComponent("support", isDirectory: true)
        )

        let input = try service.jobInput(for: audioURL, jobDirectory: jobDirectory, mode: StemJobInputMode.staged)

        XCTAssertEqual(input.stagedInputDirectory, jobDirectory.appendingPathComponent("input", isDirectory: true))
        XCTAssertEqual(input.audioPath, jobDirectory.appendingPathComponent("input/song.mp3").path)
        XCTAssertEqual(try String(contentsOfFile: input.audioPath, encoding: .utf8), "audio")
    }

    func testStemJobRequestUsesStagedAudioPathButKeepsOriginalFingerprint() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = try temporaryFile(in: directory, name: "song.mp3", contents: "audio")
        let jobDirectory = directory.appendingPathComponent("job", isDirectory: true)
        let cacheDirectory = directory.appendingPathComponent("cache", isDirectory: true)
        let fingerprint = StemSourceFingerprint(path: audioURL.path, fileSize: 5, modificationTime: 123)
        let service = StemSeparationService(
            appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { true },
            applicationSupportDirectory: directory.appendingPathComponent("support", isDirectory: true)
        )

        try service.createJobForTesting(
            audioURL: audioURL,
            fingerprint: fingerprint,
            cacheKey: "cache-key",
            cacheDirectory: cacheDirectory,
            jobDirectory: jobDirectory,
            inputMode: StemJobInputMode.staged,
            method: .sixStem
        )
        let requestData = try Data(contentsOf: jobDirectory.appendingPathComponent(StemJobFiles.requestFilename))
        let request = try JSONDecoder().decode(StemJobRequest.self, from: requestData)

        XCTAssertEqual(request.audioPath, jobDirectory.appendingPathComponent("input/song.mp3").path)
        XCTAssertEqual(request.sourceFingerprint, fingerprint)
        XCTAssertEqual(request.separationMethodID, StemSeparationMethod.sixStem.id)
        XCTAssertEqual(request.modelName, StemSeparationMethod.sixStem.modelName)
        XCTAssertEqual(request.expectedStemTypes, StemSeparationMethod.sixStem.stemTypes)
    }

    func testStemInputPermissionFailureClassification() throws {
        let service = StemSeparationService(
            appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false },
            applicationSupportDirectory: temporaryDirectory()
        )
        let path = "/Users/example/Music/song.mp3"
        let error = StemSeparationError.helperJobFailed("Failed: Operation not permitted: '\(path)'")

        XCTAssertTrue(service.isInputPermissionFailure(error, originalAudioPath: path))
        XCTAssertFalse(service.isInputPermissionFailure(error, originalAudioPath: "/other/song.mp3"))
    }
}
