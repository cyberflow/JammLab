import XCTest
@testable import JammLab

final class StemJobWorkflowTests: XCTestCase {
    func testStemJobModelsRoundTrip() throws {
        let request = StemJobRequest(
            jobID: "job-1",
            audioPath: "/tmp/song.mp3",
            cacheKey: "cache",
            cacheDirectoryPath: "/tmp/cache",
            modelDirectoryPath: "/tmp/models",
            sourceFingerprint: StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 10, modificationTime: 20),
            separationMethodID: StemSeparationMethod.vocalInstrumental.id,
            expectedStemTypes: StemSeparationMethod.vocalInstrumental.stemTypes,
            modelName: StemSeparationMethod.vocalInstrumental.modelName,
            settingsVersion: 2,
            audioSeparatorPath: nil,
            audioSeparatorBookmarkData: nil,
            computeMode: "auto",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let status = StemJobStatus(
            jobID: request.jobID,
            phase: .processing,
            progress: 0.5,
            message: "Separating stems",
            diagnostics: "stdout tail",
            backendCommand: "JammLabSeparatorHelper song.mp3",
            updatedAt: Date(timeIntervalSince1970: 101)
        )
        let metadata = StemCacheMetadata(
            cacheKey: request.cacheKey,
            sourceFingerprint: request.sourceFingerprint,
            backendIdentifier: "audio-separator",
            separationMethodID: request.separationMethodID,
            modelName: request.modelName,
            settingsVersion: request.settingsVersion,
            createdAt: Date(timeIntervalSince1970: 102),
            stems: [StemFile(type: .vocals, url: URL(fileURLWithPath: "/tmp/vocals.wav"), displayName: "Vocals")]
        )
        let result = StemJobResult(jobID: request.jobID, cacheKey: request.cacheKey, metadata: metadata, completedAt: Date(timeIntervalSince1970: 103))

        XCTAssertEqual(try JSONDecoder().decode(StemJobRequest.self, from: JSONEncoder().encode(request)), request)
        XCTAssertEqual(try JSONDecoder().decode(StemJobStatus.self, from: JSONEncoder().encode(status)), status)
        XCTAssertEqual(try JSONDecoder().decode(StemJobResult.self, from: JSONEncoder().encode(result)), result)
    }

    func testLegacyStemJobRequestWithoutAudioSeparatorPathDecodes() throws {
        let json = """
        {
          "jobID": "job-legacy",
          "audioPath": "/tmp/song.mp3",
          "cacheKey": "cache",
          "cacheDirectoryPath": "/tmp/cache",
          "modelDirectoryPath": "/tmp/models",
          "sourceFingerprint": {
            "path": "/tmp/song.mp3",
            "fileSize": 10,
            "modificationTime": 20
          },
          "modelName": "htdemucs.yaml",
          "settingsVersion": 2,
          "createdAt": 100
        }
        """

        let request = try JSONDecoder().decode(StemJobRequest.self, from: Data(json.utf8))

        XCTAssertEqual(request.jobID, "job-legacy")
        XCTAssertNil(request.audioSeparatorPath)
        XCTAssertNil(request.audioSeparatorBookmarkData)
        XCTAssertNil(request.computeMode)
        XCTAssertNil(request.separationMethodID)
        XCTAssertNil(request.expectedStemTypes)
    }

    func testStemJobFilesUseVersionedCurrentJobsDirectory() {
        let appSupport = URL(fileURLWithPath: "/tmp/JammLab", isDirectory: true)
        let jobsDirectory = StemJobFiles.currentJobsDirectory(in: appSupport)

        XCTAssertEqual(StemJobFiles.helperVersion, 5)
        XCTAssertEqual(jobsDirectory.path, "/tmp/JammLab/\(StemJobFiles.jobsDirectoryName)/v5")
        XCTAssertEqual(
            jobsDirectory.appendingPathComponent(StemJobFiles.heartbeatFilename).path,
            "/tmp/JammLab/\(StemJobFiles.jobsDirectoryName)/v5/\(StemJobFiles.heartbeatFilename)"
        )
    }

    func testStemCacheDirectoryNameIsUnversioned() {
        XCTAssertEqual(StemJobFiles.cacheDirectoryName, "StemCache")
        XCTAssertEqual(StemJobFiles.modelDirectoryName, "StemModels")
    }

    func testStemHelperHeartbeatFreshness() {
        let fresh = StemHelperHeartbeat(helperVersion: StemJobFiles.helperVersion, updatedAt: Date(), activeJobID: nil)
        let stale = StemHelperHeartbeat(helperVersion: StemJobFiles.helperVersion, updatedAt: Date().addingTimeInterval(-30), activeJobID: "job")

        XCTAssertTrue(fresh.isFresh)
        XCTAssertFalse(stale.isFresh)
    }

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

    func testStemJobStatusMapsToViewState() {
        XCTAssertEqual(StemJobPhase.pending.viewPhase.title, StemSeparationPhase.checkingBackend.title)
        XCTAssertEqual(StemJobPhase.processing.viewPhase.title, StemSeparationPhase.processing.title)
        XCTAssertEqual(StemJobPhase.completed.viewPhase.title, StemSeparationPhase.completed.title)
        XCTAssertEqual(StemJobPhase.cancelled.viewPhase.title, StemSeparationPhase.cancelled.title)
    }

    func testAudioSeparatorOutputFilenameMatching() {
        XCTAssertTrue(StemType.vocals.matchesOutputFilename("song_(Vocals)_htdemucs.wav"))
        XCTAssertTrue(StemType.instrumental.matchesOutputFilename("song_(Instrumental)_UVR-MDX-NET-Inst_HQ_5.wav"))
        XCTAssertTrue(StemType.instrumental.matchesOutputFilename("song_no_vocals.wav"))
        XCTAssertTrue(StemType.drums.matchesOutputFilename("track_drums.flac"))
        XCTAssertTrue(StemType.bass.matchesOutputFilename("bass.wav"))
        XCTAssertTrue(StemType.guitar.matchesOutputFilename("song_(Guitar)_htdemucs_6s.wav"))
        XCTAssertTrue(StemType.piano.matchesOutputFilename("song_piano.flac"))
        XCTAssertFalse(StemType.other.matchesOutputFilename("song_vocals.txt"))
        XCTAssertFalse(StemType.bass.matchesOutputFilename("drums.wav"))
    }

    func testStemTypesExposeCanonicalStemFilenames() {
        XCTAssertEqual(StemType.vocals.canonicalStemFilename, "vocals.wav")
        XCTAssertEqual(StemType.instrumental.canonicalStemFilename, "instrumental.wav")
        XCTAssertEqual(StemType.drums.canonicalStemFilename, "drums.wav")
        XCTAssertEqual(StemType.bass.canonicalStemFilename, "bass.wav")
        XCTAssertEqual(StemType.other.canonicalStemFilename, "other.wav")
        XCTAssertEqual(StemType.guitar.canonicalStemFilename, "guitar.wav")
        XCTAssertEqual(StemType.piano.canonicalStemFilename, "piano.wav")
    }

    func testHelperJobFailureDiagnosticsIncludesDetails() {
        let error = StemSeparationError.helperJobFailed(
            """
            job: /tmp/job
            command: audio-separator song.mp3
            stderr:
            backend failed
            """
        )

        XCTAssertTrue(error.diagnostics.contains("audio-separator song.mp3"))
        XCTAssertTrue(error.diagnostics.contains("backend failed"))
    }

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
