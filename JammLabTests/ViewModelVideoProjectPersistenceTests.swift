import XCTest
@testable import JammLab

final class ViewModelVideoProjectPersistenceTests: XCTestCase {
    @MainActor
    func testOpeningVideoProjectWithoutLocalAudioDoesNotCreateProjectMediaDirectory() async throws {
        let missingVideoURL = try temporaryFile(name: "missing-video.mov", contents: "video")
        let projectDirectory = temporaryDirectory()
        let projectURL = projectDirectory.appendingPathComponent("video-readonly.jammlab")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: missingVideoURL)
            try? FileManager.default.removeItem(at: projectDirectory)
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: missingVideoURL),
            audioDisplayName: "lesson.mov",
            audioDuration: 0.5,
            mediaKind: .video,
            notes: [],
            loopStart: 0,
            loopEnd: 0.5,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        try FileManager.default.removeItem(at: missingVideoURL)
        let entry = RecentProjectEntry(
            displayName: "video-readonly",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let artifactStore = ProjectArtifactStore()
        let viewModel = AudioPlayerViewModel(
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            projectArtifactStore: artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.importedFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactStore.mediaDirectory(for: projectURL).path))
    }

    @MainActor
    func testSaveProjectPersistsVideoWindowOpenState() async throws {
        let audioURL = try temporaryAudioFile()
        let videoURL = try temporaryFile(name: "lesson.mov", contents: "video")
        let projectURL = temporaryDirectory().appendingPathComponent("video-window-save.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: videoURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)

        let didSaveOpenState = await viewModel.saveProject(to: projectURL)
        XCTAssertTrue(didSaveOpenState)
        XCTAssertEqual(try projectService.load(from: projectURL).isVideoWindowOpen, true)
        XCTAssertFalse(viewModel.isProjectModified)

        videoFollower.closeWindow()

        XCTAssertTrue(viewModel.isProjectModified)
        let didSaveClosedState = await viewModel.saveProject(to: projectURL)
        XCTAssertTrue(didSaveClosedState)
        XCTAssertEqual(try projectService.load(from: projectURL).isVideoWindowOpen, false)
        XCTAssertFalse(viewModel.isProjectModified)
    }

}
