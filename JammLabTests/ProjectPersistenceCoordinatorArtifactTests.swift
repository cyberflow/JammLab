import XCTest
@testable import JammLab

final class ProjectPersistenceCoordinatorArtifactTests: XCTestCase {
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

private extension ProjectPersistenceCoordinatorArtifactTests {
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
