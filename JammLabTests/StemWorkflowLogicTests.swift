import XCTest
@testable import JammLab

final class StemWorkflowLogicTests: XCTestCase {
    func testStemMixMuteSoloPrecedenceAndVolumeClamping() {
        var mix = StemMixState(items: [
            StemMixItem(type: .vocals, volume: 1, isAvailable: true),
            StemMixItem(type: .drums, volume: 0.75, isAvailable: true),
            StemMixItem(type: .bass, volume: 0.5, isAvailable: true),
            StemMixItem(type: .other, volume: 1, isAvailable: false)
        ])

        XCTAssertEqual(mix.effectiveVolume(for: .vocals), 1, accuracy: 0.0001)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 0.5, accuracy: 0.0001)
        XCTAssertTrue(mix.isAudible(.vocals))
        XCTAssertFalse(mix.isAudible(.other))

        mix.update(.vocals) { $0.isMuted = true }
        XCTAssertEqual(mix.effectiveVolume(for: .vocals), 0, accuracy: 0.0001)
        XCTAssertFalse(mix.isAudible(.vocals))
        XCTAssertTrue(mix.isAudible(.drums))

        mix.update(.bass) { $0.isSoloed = true }
        XCTAssertEqual(mix.effectiveVolume(for: .drums), 0, accuracy: 0.0001)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 0.5, accuracy: 0.0001)
        XCTAssertEqual(mix.effectiveVolume(for: .vocals), 0, accuracy: 0.0001)
        XCTAssertFalse(mix.isAudible(.drums))
        XCTAssertTrue(mix.isAudible(.bass))
        XCTAssertFalse(mix.isAudible(.vocals))

        mix.update(.bass) {
            $0.volume = 2
            $0.isMuted = true
        }
        XCTAssertEqual(mix.item(for: .bass).volume, 1, accuracy: 0.0001)
        XCTAssertTrue(mix.item(for: .bass).isMuted)
        XCTAssertTrue(mix.item(for: .bass).isSoloed)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 1, accuracy: 0.0001)
        XCTAssertTrue(mix.isAudible(.bass))

        mix.update(.bass) { $0.isSoloed = false }
        XCTAssertTrue(mix.item(for: .bass).isMuted)
        XCTAssertFalse(mix.item(for: .bass).isSoloed)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 0, accuracy: 0.0001)
        XCTAssertFalse(mix.isAudible(.bass))
    }

    func testStemMixResetUsesStemVolumeGroupDefault() {
        var mix = StemMixState(items: [
            StemMixItem(type: .vocals, volume: 0.2, isMuted: true, isAvailable: true),
            StemMixItem(type: .drums, volume: 0.4, isSoloed: true, isAvailable: true)
        ])

        mix.resetMix(availableStems: [
            StemFile(type: .vocals, url: URL(fileURLWithPath: "/tmp/vocals.wav"), displayName: "Vocals")
        ])

        XCTAssertEqual(mix.item(for: .vocals).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertEqual(mix.item(for: .drums).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertTrue(mix.item(for: .vocals).isAvailable)
        XCTAssertFalse(mix.item(for: .drums).isAvailable)
        XCTAssertFalse(mix.item(for: .vocals).isMuted)
        XCTAssertFalse(mix.item(for: .drums).isSoloed)
    }

    func testProjectVersionSevenPersistsProjectEditablePlaybackStateMediaKindArtifactRootBookmarkAndVideoWindowState() throws {
        let artifactRootBookmarkData = Data("artifact-root-bookmark".utf8)
        let metadata = StemProjectState(
            cacheKey: "cache-123",
            sourceFingerprint: StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 42, modificationTime: 1234),
            backendIdentifier: "demucs:/opt/homebrew/bin/demucs",
            modelName: "htdemucs",
            settingsVersion: 1,
            playbackMode: .stems,
            mixState: StemMixState(items: [
                StemMixItem(type: .vocals, volume: 0, isMuted: true, isSoloed: false, isAvailable: true),
                StemMixItem(type: .drums, volume: 0.8, isMuted: false, isSoloed: true, isAvailable: true)
            ])
        )
        let project = JammLabProject(
            audioBookmarkData: Data("bookmark".utf8),
            artifactRootBookmarkData: artifactRootBookmarkData,
            audioDisplayName: "lesson.mp4",
            audioDuration: 120,
            mediaKind: .video,
            notes: [],
            loopStart: 0,
            loopEnd: 120,
            isLoopEnabled: true,
            playbackRate: 1,
            pitchShiftSemitones: 0,
            tempoBPM: 120,
            beatGridSettings: BeatGridSettings(bpm: 120, timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4)),
            mainTrackVolume: 0.64,
            isClickEnabled: true,
            clickVolume: 0.42,
            isSnapEnabled: true,
            playbackMode: .stems,
            stemState: metadata,
            isVideoWindowOpen: true
        )

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded.formatVersion, 7)
        XCTAssertEqual(decoded.artifactRootBookmarkData, artifactRootBookmarkData)
        XCTAssertEqual(decoded.mediaKind, .video)
        XCTAssertEqual(decoded.isLoopEnabled, true)
        XCTAssertEqual(decoded.mainTrackVolume, 0.64)
        XCTAssertEqual(decoded.beatGridSettings?.timeSignature, TimeSignature(beatsPerBar: 7, beatUnit: 4))
        XCTAssertEqual(decoded.isClickEnabled, true)
        XCTAssertEqual(decoded.clickVolume, 0.42)
        XCTAssertEqual(decoded.isSnapEnabled, true)
        XCTAssertEqual(decoded.playbackMode, .stems)
        XCTAssertEqual(decoded.isVideoWindowOpen, true)
        XCTAssertEqual(decoded.stemState?.cacheKey, "cache-123")
        XCTAssertEqual(decoded.stemState?.playbackMode, .stems)
        XCTAssertEqual(try XCTUnwrap(decoded.stemState?.mixState.effectiveVolume(for: .vocals)), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(decoded.stemState?.mixState.effectiveVolume(for: .drums)), 0.8, accuracy: 0.0001)
    }

    func testStemFingerprintCanMatchSameFileThroughDifferentPath() {
        let original = StemSourceFingerprint(path: "/Users/me/Music/song.mp3", fileSize: 42, modificationTime: 1234)
        let resolvedBookmark = StemSourceFingerprint(path: "/private/var/folders/song.mp3", fileSize: 42, modificationTime: 1234)
        let editedFile = StemSourceFingerprint(path: "/Users/me/Music/song.mp3", fileSize: 43, modificationTime: 1234)

        XCTAssertTrue(original.hasSameFileIdentity(as: resolvedBookmark))
        XCTAssertFalse(original.hasSameFileIdentity(as: editedFile))
    }

    func testStemSeparationMethodsExposeModelsAndStemOrder() {
        XCTAssertEqual(StemSeparationMethod.allCases.map(\.id), ["vocalInstrumental", "fourStem"])
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.modelName, "UVR-MDX-NET-Inst_HQ_5.onnx")
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.stemTypes, [.vocals, .instrumental])
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.stemCountSummary, "2 stems: vocals and instrumental.")
        XCTAssertEqual(StemSeparationMethod.fourStem.modelName, "htdemucs.yaml")
        XCTAssertEqual(StemSeparationMethod.fourStem.stemTypes, [.vocals, .bass, .drums, .other])
        XCTAssertEqual(StemSeparationMethod.fourStem.stemCountSummary, "4 stems: vocals, bass, drums, and other.")
    }

    func testLegacyProjectWithoutStemStateStillDecodes() throws {
        let json = """
        {
          "formatVersion": 1,
          "audioBookmarkData": "Ym9va21hcms=",
          "audioDisplayName": "legacy.mp3",
          "audioDuration": 90,
          "notes": [],
          "loopStart": 0,
          "loopEnd": 90,
          "playbackRate": 1,
          "pitchShiftSemitones": 0,
          "tempoBPM": 120,
          "beatGridSettings": null
        }
        """

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.audioDisplayName, "legacy.mp3")
        XCTAssertNil(decoded.artifactRootBookmarkData)
        XCTAssertNil(decoded.stemState)
        XCTAssertNil(decoded.mainTrackVolume)
        XCTAssertNil(decoded.isLoopEnabled)
        XCTAssertNil(decoded.isClickEnabled)
        XCTAssertNil(decoded.clickVolume)
        XCTAssertNil(decoded.isSnapEnabled)
        XCTAssertNil(decoded.playbackMode)
        XCTAssertNil(decoded.mediaKind)
        XCTAssertNil(decoded.isVideoWindowOpen)
    }

    func testMediaImporterClassifiesSupportedFormats() {
        let importer = AudioFileImporter()

        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/song.mp3")), .audio)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/song.wav")), .audio)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/lesson.mp4")), .video)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/lesson.mov")), .video)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/lesson.m4v")), .video)
        XCTAssertNil(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/document.pdf")))
    }

    func testMediaCacheKeyIsStableForSameFileIdentity() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try temporaryFile(in: directory, name: "lesson.mp4", contents: "video")
        let modificationDate = Date(timeIntervalSince1970: 1234)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)

        let firstKey = VideoAudioExtractionService.cacheKey(for: url)
        let secondKey = VideoAudioExtractionService.cacheKey(for: url)

        XCTAssertEqual(firstKey, secondKey)

        let changedURL = try temporaryFile(in: directory, name: "changed-lesson.mp4", contents: "changed-video")
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate.addingTimeInterval(10)],
            ofItemAtPath: changedURL.path
        )

        XCTAssertNotEqual(VideoAudioExtractionService.cacheKey(for: changedURL), firstKey)
    }

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

        XCTAssertEqual(StemJobFiles.helperVersion, 4)
        XCTAssertEqual(jobsDirectory.path, "/tmp/JammLab/\(StemJobFiles.jobsDirectoryName)/v4")
        XCTAssertEqual(
            jobsDirectory.appendingPathComponent(StemJobFiles.heartbeatFilename).path,
            "/tmp/JammLab/\(StemJobFiles.jobsDirectoryName)/v4/\(StemJobFiles.heartbeatFilename)"
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
        XCTAssertFalse(StemType.other.matchesOutputFilename("song_vocals.txt"))
        XCTAssertFalse(StemType.bass.matchesOutputFilename("drums.wav"))
    }

    func testStemTypesExposeCanonicalStemFilenames() {
        XCTAssertEqual(StemType.vocals.canonicalStemFilename, "vocals.wav")
        XCTAssertEqual(StemType.instrumental.canonicalStemFilename, "instrumental.wav")
        XCTAssertEqual(StemType.drums.canonicalStemFilename, "drums.wav")
        XCTAssertEqual(StemType.bass.canonicalStemFilename, "bass.wav")
        XCTAssertEqual(StemType.other.canonicalStemFilename, "other.wav")
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
            inputMode: StemJobInputMode.staged
        )
        let requestData = try Data(contentsOf: jobDirectory.appendingPathComponent(StemJobFiles.requestFilename))
        let request = try JSONDecoder().decode(StemJobRequest.self, from: requestData)

        XCTAssertEqual(request.audioPath, jobDirectory.appendingPathComponent("input/song.mp3").path)
        XCTAssertEqual(request.sourceFingerprint, fingerprint)
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

    func testProjectArtifactStoreRoundTripsStemMetadataAndFiles() throws {
        let directory = temporaryDirectory()
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceFingerprint = StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 42, modificationTime: 123)
        let metadata = StemCacheMetadata(
            cacheKey: "cache-key",
            sourceFingerprint: sourceFingerprint,
            backendIdentifier: "JammLabSeparatorHelper/test",
            separationMethodID: StemSeparationMethod.fourStem.id,
            modelName: StemSeparationMethod.fourStem.modelName,
            settingsVersion: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            stems: try StemSeparationMethod.fourStem.stemTypes.map { type in
                let url = try temporaryFile(in: sourceDirectory, name: "\(type.rawValue)-source.wav", contents: type.rawValue)
                return StemFile(type: type, url: url, displayName: type.title)
            }
        )
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        let localMetadata = try store.writeStemMetadata(metadata, projectURL: projectURL)
        let restored = try XCTUnwrap(store.readStemMetadata(
            projectURL: projectURL,
            expectedFingerprint: sourceFingerprint
        ))

        XCTAssertEqual(localMetadata.cacheKey, metadata.cacheKey)
        XCTAssertEqual(restored.cacheKey, metadata.cacheKey)
        XCTAssertEqual(restored.sourceFingerprint, sourceFingerprint)
        XCTAssertEqual(restored.separationMethodID, StemSeparationMethod.fourStem.id)
        XCTAssertEqual(Set(restored.stems.map(\.type)), Set(StemSeparationMethod.fourStem.stemTypes))
        for stem in restored.stems {
            XCTAssertEqual(stem.url.deletingLastPathComponent(), store.stemsDirectory(for: projectURL))
            XCTAssertEqual(stem.url.lastPathComponent, stem.type.canonicalStemFilename)
            XCTAssertEqual(try String(contentsOf: stem.url, encoding: .utf8), stem.type.rawValue)
        }
    }

    func testProjectArtifactStoreRoundTripsVocalInstrumentalStemMetadataAndFiles() throws {
        let directory = temporaryDirectory()
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceFingerprint = StemSourceFingerprint(path: "/tmp/song.mp3", fileSize: 42, modificationTime: 123)
        let metadata = StemCacheMetadata(
            cacheKey: "cache-key-2",
            sourceFingerprint: sourceFingerprint,
            backendIdentifier: "JammLabSeparatorHelper/test",
            separationMethodID: StemSeparationMethod.vocalInstrumental.id,
            modelName: StemSeparationMethod.vocalInstrumental.modelName,
            settingsVersion: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            stems: try StemSeparationMethod.vocalInstrumental.stemTypes.map { type in
                let url = try temporaryFile(in: sourceDirectory, name: "\(type.rawValue)-source.wav", contents: type.rawValue)
                return StemFile(type: type, url: url, displayName: type.title)
            }
        )
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        _ = try store.writeStemMetadata(metadata, projectURL: projectURL)
        let restored = try XCTUnwrap(store.readStemMetadata(
            projectURL: projectURL,
            expectedFingerprint: sourceFingerprint
        ))

        XCTAssertEqual(restored.separationMethodID, StemSeparationMethod.vocalInstrumental.id)
        XCTAssertEqual(restored.stems.map(\.type), [.vocals, .instrumental])
        XCTAssertEqual(restored.stems.map(\.displayName), ["Vocals", "Instrumental"])
    }

    func testProjectArtifactStorePersistsVideoAudioBesideProject() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let extractedAudioURL = try temporaryFile(in: directory, name: "cached-audio.m4a", contents: "audio")
        let videoURL = directory.appendingPathComponent("lesson.mp4")
        let file = ImportedAudioFile(
            url: extractedAudioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mp4",
            duration: 12,
            mediaKind: .video
        )
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()

        let persisted = try store.persistVideoAudioIfNeeded(file, projectURL: projectURL)

        XCTAssertEqual(persisted.url, store.videoAudioURL(for: projectURL))
        XCTAssertEqual(persisted.sourceMediaURL, videoURL)
        XCTAssertEqual(persisted.mediaKind, .video)
        XCTAssertEqual(try String(contentsOf: persisted.url, encoding: .utf8), "audio")
        XCTAssertEqual(store.existingVideoAudioURL(for: projectURL), persisted.url)
    }

    func testProjectPersistenceCoordinatorPersistsVideoAudioAndReturnsTemporaryCleanupURL() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cachedAudioURL = try temporaryFile(in: directory, name: "cached-audio.m4a", contents: "audio")
        let videoURL = directory.appendingPathComponent("lesson.mov")
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()
        let coordinator = try makeProjectPersistenceCoordinator(projectArtifactStore: store)
        let input = ProjectSaveArtifactsInput(
            importedFile: ImportedAudioFile(
                url: cachedAudioURL,
                sourceMediaURL: videoURL,
                displayName: "lesson.mov",
                duration: 12,
                mediaKind: .video
            ),
            projectURL: projectURL,
            peakformData: nil,
            stemPeakforms: [:],
            stemFiles: [],
            stemCacheMetadata: nil
        )

        let result = try await coordinator.prepareSaveArtifacts(input)

        XCTAssertEqual(result.importedFile?.url, store.videoAudioURL(for: projectURL))
        XCTAssertEqual(result.temporaryVideoAudioURLToRemove, cachedAudioURL)
        XCTAssertEqual(try String(contentsOf: store.videoAudioURL(for: projectURL), encoding: .utf8), "audio")
    }

    func testProjectPersistenceCoordinatorWritesPeakformsAndStemMetadata() async throws {
        let directory = temporaryDirectory()
        let stemSourceDirectory = directory.appendingPathComponent("stem-source", isDirectory: true)
        try FileManager.default.createDirectory(at: stemSourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = try temporaryFile(in: directory, name: "song.wav", contents: "audio")
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let store = ProjectArtifactStore()
        let coordinator = try makeProjectPersistenceCoordinator(projectArtifactStore: store)
        let peakform = PeakformData(
            duration: 1,
            sampleRate: 44_100,
            levels: [PeakformLevel(samplesPerPeak: 512, peaks: [PeakPoint(min: -0.5, max: 0.5, rms: 0.2)])]
        )
        let stems = try StemSeparationMethod.fourStem.stemTypes.map { type in
            StemFile(
                type: type,
                url: try temporaryFile(in: stemSourceDirectory, name: "\(type.rawValue).wav", contents: type.rawValue),
                displayName: type.title
            )
        }
        let metadata = StemCacheMetadata(
            cacheKey: "cache-key",
            sourceFingerprint: StemSourceFingerprint(path: audioURL.path, fileSize: 5, modificationTime: 10),
            backendIdentifier: "JammLabSeparatorHelper/test",
            separationMethodID: StemSeparationMethod.fourStem.id,
            modelName: StemSeparationMethod.fourStem.modelName,
            settingsVersion: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            stems: stems
        )
        let input = ProjectSaveArtifactsInput(
            importedFile: ImportedAudioFile(url: audioURL, displayName: "song.wav", duration: 1),
            projectURL: projectURL,
            peakformData: peakform,
            stemPeakforms: [.vocals: peakform],
            stemFiles: stems,
            stemCacheMetadata: metadata
        )

        let result = try await coordinator.prepareSaveArtifacts(input)

        XCTAssertNotNil(try store.readMainPeakform(projectURL: projectURL))
        XCTAssertNotNil(try store.readStemPeakform(type: .vocals, projectURL: projectURL))
        XCTAssertEqual(result.peakformURLsToRemove, [audioURL] + stems.map(\.url))
        XCTAssertEqual(result.stemMetadata?.cacheKey, metadata.cacheKey)
        XCTAssertEqual(result.stemCacheKeyToRemove, metadata.cacheKey)
        XCTAssertEqual(result.stemMetadata?.stems.map { $0.url.deletingLastPathComponent() }, Array(repeating: store.stemsDirectory(for: projectURL), count: StemSeparationMethod.fourStem.stemTypes.count))
    }

    func testProjectPersistenceCoordinatorOpenMediaPrefersProjectLocalVideoAudio() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let projectService = ProjectDocumentService()
        let store = ProjectArtifactStore()
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let videoURL = try temporaryFile(in: directory, name: "lesson.mov", contents: "video")
        try FileManager.default.createDirectory(at: store.mediaDirectory(for: projectURL), withIntermediateDirectories: true)
        let localAudioURL = store.videoAudioURL(for: projectURL)
        try Data("local-audio".utf8).write(to: localAudioURL)
        let coordinator = try makeProjectPersistenceCoordinator(
            projectArtifactStore: store,
            decodedDuration: { url in
                XCTAssertEqual(url, localAudioURL)
                return 9
            }
        )
        let project = videoProject(bookmarkData: try projectService.bookmarkData(for: videoURL), duration: 12)

        let result = try await coordinator.resolveProjectMedia(project: project, projectURL: projectURL)

        XCTAssertEqual(result.file.url, localAudioURL)
        XCTAssertEqual(result.file.sourceMediaURL, videoURL)
        XCTAssertEqual(result.file.mediaKind, .video)
        XCTAssertEqual(result.projectDuration, 9)
        XCTAssertFalse(result.shouldAnalyzeTempo)
        XCTAssertNil(result.warningMessage)
    }

    func testProjectPersistenceCoordinatorOpenVideoWithoutLocalAudioUsesRuntimeCacheOnly() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let projectService = ProjectDocumentService()
        let store = ProjectArtifactStore()
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        let videoURL = try temporaryFile(in: directory, name: "lesson.mov", contents: "video")
        let extractedAudioURL = try temporaryFile(in: directory, name: "runtime-audio.m4a", contents: "audio")
        let coordinator = try makeProjectPersistenceCoordinator(
            projectArtifactStore: store,
            importFileFromURL: { url in
                XCTAssertEqual(url, videoURL)
                return ImportedAudioFile(
                    url: extractedAudioURL,
                    sourceMediaURL: url,
                    displayName: url.lastPathComponent,
                    duration: 7,
                    mediaKind: .video
                )
            }
        )
        let project = videoProject(bookmarkData: try projectService.bookmarkData(for: videoURL), duration: 12)

        let result = try await coordinator.resolveProjectMedia(project: project, projectURL: projectURL)

        XCTAssertEqual(result.file.url, extractedAudioURL)
        XCTAssertEqual(result.file.sourceMediaURL, videoURL)
        XCTAssertEqual(result.file.mediaKind, .video)
        XCTAssertEqual(result.projectDuration, 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.mediaDirectory(for: projectURL).path))
    }

    func testProjectPersistenceCoordinatorMissingVideoSourceFallsBackToLocalAudioWithWarning() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectArtifactStore()
        let projectURL = directory.appendingPathComponent("Song.jammlab")
        try FileManager.default.createDirectory(at: store.mediaDirectory(for: projectURL), withIntermediateDirectories: true)
        let localAudioURL = store.videoAudioURL(for: projectURL)
        try Data("local-audio".utf8).write(to: localAudioURL)
        let coordinator = try makeProjectPersistenceCoordinator(
            projectArtifactStore: store,
            decodedDuration: { url in
                XCTAssertEqual(url, localAudioURL)
                return 6
            }
        )
        let project = videoProject(bookmarkData: Data("invalid-bookmark".utf8), duration: 12)

        let result = try await coordinator.resolveProjectMedia(project: project, projectURL: projectURL)

        XCTAssertEqual(result.file.url, localAudioURL)
        XCTAssertEqual(result.file.sourceMediaURL, localAudioURL)
        XCTAssertEqual(result.file.mediaKind, .audio)
        XCTAssertNil(result.file.videoURL)
        XCTAssertEqual(result.projectDuration, 6)
        XCTAssertNotNil(result.warningMessage)
    }

}

private extension StemWorkflowLogicTests {
    func makeProjectPersistenceCoordinator(
        projectArtifactStore: ProjectArtifactStore,
        importFileFromURL: ((URL) async throws -> ImportedAudioFile)? = nil,
        decodedDuration: @escaping (URL) throws -> TimeInterval = { _ in 1 }
    ) throws -> ProjectPersistenceCoordinator {
        ProjectPersistenceCoordinator(
            projectArtifactStore: projectArtifactStore,
            projectDocumentService: ProjectDocumentService(),
            peakformProvider: MockPeakformProvider(),
            stemSeparationService: StemSeparationService(
                appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
                applicationSupportDirectory: temporaryDirectory()
            ),
            importFileFromURL: importFileFromURL,
            decodedDuration: decodedDuration
        )
    }

    func videoProject(bookmarkData: Data, duration: TimeInterval) -> JammLabProject {
        JammLabProject(
            audioBookmarkData: bookmarkData,
            audioDisplayName: "lesson.mov",
            audioDuration: duration,
            mediaKind: .video,
            notes: [],
            loopStart: 0,
            loopEnd: duration,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
    }
}
