import XCTest
@testable import JammLab

final class StemJobWorkflowTests: XCTestCase {
    func testStemJobModelsRoundTrip() throws {
        let request = StemJobRequest(
            protocolVersion: StemJobFiles.protocolVersion,
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

    func testV6StemJobRequestRejectsLegacyPayload() throws {
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

        XCTAssertThrowsError(
            try JSONDecoder().decode(StemJobRequest.self, from: Data(json.utf8))
        )
    }

    func testStemJobFilesUseVersionedCurrentJobsDirectory() {
        let appSupport = URL(fileURLWithPath: "/tmp/JammLab", isDirectory: true)
        let jobsDirectory = StemJobFiles.currentJobsDirectory(in: appSupport)

        XCTAssertEqual(StemJobFiles.helperVersion, 6)
        XCTAssertEqual(StemJobFiles.protocolVersion, 6)
        XCTAssertEqual(jobsDirectory.path, "/tmp/JammLab/\(StemJobFiles.jobsDirectoryName)/v6")
        XCTAssertEqual(
            jobsDirectory.appendingPathComponent(StemJobFiles.heartbeatFilename).path,
            "/tmp/JammLab/\(StemJobFiles.jobsDirectoryName)/v6/\(StemJobFiles.heartbeatFilename)"
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

}
