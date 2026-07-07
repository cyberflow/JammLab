import XCTest
@testable import JammLab

final class ViewModelVideoProjectPersistenceTests: XCTestCase {
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

    @MainActor
    func testOpenProjectRestoresSavedVideoWindowOpenState() async throws {
        let fixture = try makeVideoProjectFixture(
            name: "video-window-open",
            isVideoWindowOpen: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: fixture.projectService,
            projectArtifactStore: fixture.artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openProject(at: fixture.projectURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(videoFollower.loadedVideoURL, fixture.videoURL)
        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testOpenProjectClosesVideoWindowWhenSavedStateIsClosed() async throws {
        let fixture = try makeVideoProjectFixture(
            name: "video-window-closed",
            isVideoWindowOpen: false
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: fixture.projectService,
            projectArtifactStore: fixture.artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )
        videoFollower.showWindow(at: 0, isPlaying: false, rate: 1)

        await viewModel.openProject(at: fixture.projectURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertFalse(videoFollower.isWindowOpen)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
        XCTAssertGreaterThanOrEqual(videoFollower.closeWindowCount, 1)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testOpenLegacyVideoProjectWithoutWindowStateKeepsVideoWindowClosed() async throws {
        let fixture = try makeVideoProjectFixture(
            name: "video-window-legacy",
            isVideoWindowOpen: nil
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: fixture.projectService,
            projectArtifactStore: fixture.artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openProject(at: fixture.projectURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertFalse(videoFollower.isWindowOpen)
        XCTAssertTrue(videoFollower.showWindowEvents.isEmpty)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    private struct VideoProjectFixture {
        let directory: URL
        let projectURL: URL
        let videoURL: URL
        let projectService: ProjectDocumentService
        let artifactStore: ProjectArtifactStore
    }

    private func makeVideoProjectFixture(
        name: String,
        isVideoWindowOpen: Bool?
    ) throws -> VideoProjectFixture {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let projectURL = directory.appendingPathComponent("\(name).jammlab")
        let videoURL = try temporaryFile(in: directory, name: "\(name).mov", contents: "video")
        let localAudioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: localAudioURL) }

        let artifactStore = ProjectArtifactStore()
        try FileManager.default.createDirectory(
            at: artifactStore.mediaDirectory(for: projectURL),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: localAudioURL,
            to: artifactStore.videoAudioURL(for: projectURL)
        )

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: videoURL),
            audioDisplayName: videoURL.lastPathComponent,
            audioDuration: 0.5,
            mediaKind: .video,
            notes: [],
            loopStart: 0,
            loopEnd: 0.5,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            isVideoWindowOpen: isVideoWindowOpen
        )
        try projectService.save(project, to: projectURL)

        return VideoProjectFixture(
            directory: directory,
            projectURL: projectURL,
            videoURL: videoURL,
            projectService: projectService,
            artifactStore: artifactStore
        )
    }
}
