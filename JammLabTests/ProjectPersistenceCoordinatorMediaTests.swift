import XCTest
@testable import JammLab

final class ProjectPersistenceCoordinatorMediaTests: XCTestCase {
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

private extension ProjectPersistenceCoordinatorMediaTests {
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
