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

    func testStemMixStateDecodeNormalizesMissingNewStemTypes() throws {
        let json = """
        {
          "items": [
            {
              "type": "vocals",
              "volume": 0.25,
              "isMuted": true,
              "isSoloed": false,
              "isAvailable": true
            },
            {
              "type": "drums",
              "volume": 0.5,
              "isMuted": false,
              "isSoloed": true,
              "isAvailable": true
            }
          ]
        }
        """

        var mix = try JSONDecoder().decode(StemMixState.self, from: Data(json.utf8))

        XCTAssertEqual(mix.items.map(\.type), StemType.allCases)
        XCTAssertEqual(mix.item(for: .vocals).volume, 0.25, accuracy: 0.0001)
        XCTAssertTrue(mix.item(for: .vocals).isMuted)
        XCTAssertTrue(mix.item(for: .drums).isSoloed)
        XCTAssertEqual(mix.item(for: .guitar).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertFalse(mix.item(for: .piano).isAvailable)

        let sixStemFiles = StemSeparationMethod.sixStem.stemTypes.map { type in
            StemFile(type: type, url: URL(fileURLWithPath: "/tmp/\(type.canonicalStemFilename)"), displayName: type.title)
        }
        mix.setAvailability(from: sixStemFiles)

        XCTAssertTrue(mix.item(for: .guitar).isAvailable)
        XCTAssertTrue(mix.item(for: .piano).isAvailable)
        XCTAssertFalse(mix.item(for: .instrumental).isAvailable)
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
            playbackMarkerTime: 12.5,
            stemState: metadata,
            isVideoWindowOpen: true,
            isNotationTrackCollapsed: false
        )

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded.formatVersion, 10)
        XCTAssertEqual(decoded.artifactRootBookmarkData, artifactRootBookmarkData)
        XCTAssertEqual(decoded.mediaKind, .video)
        XCTAssertEqual(decoded.isLoopEnabled, true)
        XCTAssertEqual(decoded.mainTrackVolume, 0.64)
        XCTAssertEqual(decoded.beatGridSettings?.timeSignature, TimeSignature(beatsPerBar: 7, beatUnit: 4))
        XCTAssertEqual(decoded.isClickEnabled, true)
        XCTAssertEqual(decoded.clickVolume, 0.42)
        XCTAssertEqual(decoded.playbackMarkerTime, 12.5)
        XCTAssertEqual(decoded.isSnapEnabled, true)
        XCTAssertEqual(decoded.playbackMode, .stems)
        XCTAssertEqual(decoded.isVideoWindowOpen, true)
        XCTAssertEqual(decoded.isNotationTrackCollapsed, false)
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
        XCTAssertEqual(StemSeparationMethod.allCases.map(\.id), ["vocalInstrumental", "fourStem", "sixStem"])
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.modelName, "UVR-MDX-NET-Inst_HQ_5.onnx")
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.stemTypes, [.vocals, .instrumental])
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.stemCountSummary, "2 stems: vocals and instrumental.")
        XCTAssertEqual(StemSeparationMethod.fourStem.modelName, "htdemucs.yaml")
        XCTAssertEqual(StemSeparationMethod.fourStem.stemTypes, [.vocals, .bass, .drums, .other])
        XCTAssertEqual(StemSeparationMethod.fourStem.stemCountSummary, "4 stems: vocals, bass, drums, and other.")
        XCTAssertEqual(StemSeparationMethod.sixStem.modelName, "htdemucs_6s.yaml")
        XCTAssertEqual(StemSeparationMethod.sixStem.stemTypes, [.vocals, .bass, .drums, .other, .guitar, .piano])
        XCTAssertEqual(StemSeparationMethod.sixStem.stemCountSummary, "6 stems: vocals, bass, drums, other, guitar, and piano.")
    }

    func testTimelineStemTrackHeightExpandsForSixStemRows() {
        let defaultHeight = AppTheme.Timeline.stemTracksHeight
        let sixStemHeight = AppTheme.Timeline.stemTracksHeight(rowCount: StemSeparationMethod.sixStem.stemTypes.count)

        XCTAssertEqual(AppTheme.Timeline.stemTracksHeight(rowCount: StemSeparationMethod.vocalInstrumental.stemTypes.count), defaultHeight)
        XCTAssertEqual(AppTheme.Timeline.stemTracksHeight(rowCount: StemSeparationMethod.fourStem.stemTypes.count), defaultHeight)
        XCTAssertGreaterThan(sixStemHeight, defaultHeight)
        XCTAssertGreaterThan(
            AppTheme.Timeline.tracksMinimumHeight(stemRowCount: StemSeparationMethod.sixStem.stemTypes.count),
            AppTheme.Timeline.tracksMinimumHeight
        )
    }

    func testTimelineHeightHelpersCollapseNotationTrackWithoutChangingStemExpansion() {
        let collapsedHeight = AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: StemSeparationMethod.defaultValue.stemTypes.count,
            isNotationTrackCollapsed: true
        )
        let expandedHeight = AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: StemSeparationMethod.defaultValue.stemTypes.count,
            isNotationTrackCollapsed: false
        )
        let sixStemCollapsedHeight = AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: StemSeparationMethod.sixStem.stemTypes.count,
            isNotationTrackCollapsed: true
        )

        XCTAssertLessThan(collapsedHeight, expandedHeight)
        XCTAssertEqual(
            expandedHeight - collapsedHeight,
            AppTheme.Timeline.notationTrackHeight - AppTheme.Timeline.notationTrackCollapsedHeight,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(sixStemCollapsedHeight, collapsedHeight)
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
        XCTAssertNil(decoded.isNotationTrackCollapsed)
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
