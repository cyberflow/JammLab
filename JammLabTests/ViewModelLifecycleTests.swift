import XCTest
@testable import JammLab

final class ViewModelLifecycleTests: XCTestCase {
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
    func testSelectionOnlyRegionFocusDoesNotMarkProjectModified() async throws {
        let audioURL = try temporaryAudioFile(duration: 2)
        let projectURL = temporaryDirectory().appendingPathComponent("selection.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let region = TimecodedNote(kind: .region, time: 0.25, duration: 0.5, title: "Region")
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 2,
            notes: [region],
            loopStart: 0,
            loopEnd: 2,
            isLoopEnabled: false,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "selection",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openRecentProject(entry)

        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.focusRegion(id: region.id)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSaveProjectForClosePersistsAndClearsModifiedState() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("save-close.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 0.5,
            notes: [],
            loopStart: 0,
            loopEnd: 0.5,
            isLoopEnabled: false,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "save-close",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openRecentProject(entry)
        viewModel.setMainTrackVolume(0.2)

        XCTAssertTrue(viewModel.isProjectModified)

        let didSave = await viewModel.saveProjectForClose()

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.isProjectModified)

        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(try XCTUnwrap(savedProject.mainTrackVolume), 0.2, accuracy: 0.0001)
        XCTAssertNotNil(savedProject.artifactRootBookmarkData)
        XCTAssertNil(savedProject.isVideoWindowOpen)
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

    @MainActor
    func testNotationTrackCollapsedDefaultsToClosedForImportedMediaAndPersistsChanges() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("notation-collapse-save.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "notation.wav", duration: 0.5)

        try viewModel.loadImportedAudio(media)

        XCTAssertTrue(viewModel.isNotationTrackCollapsed)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.setNotationTrackCollapsed(false)

        XCTAssertFalse(viewModel.isNotationTrackCollapsed)
        XCTAssertTrue(viewModel.isProjectModified)

        let didSave = await viewModel.saveProject(to: projectURL)

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertEqual(try projectService.load(from: projectURL).isNotationTrackCollapsed, false)
    }

    @MainActor
    func testOpenProjectRestoresNotationTrackCollapsedStateAndKeepsLegacyClean() async throws {
        let audioURL = try temporaryAudioFile()
        let directory = temporaryDirectory()
        let expandedProjectURL = directory.appendingPathComponent("notation-expanded.jammlab")
        let collapsedProjectURL = directory.appendingPathComponent("notation-collapsed.jammlab")
        let legacyProjectURL = directory.appendingPathComponent("notation-legacy.jammlab")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: directory)
        }

        let projectService = ProjectDocumentService()
        try projectService.save(
            notationCollapseProject(audioURL: audioURL, projectService: projectService, collapsed: false),
            to: expandedProjectURL
        )
        try projectService.save(
            notationCollapseProject(audioURL: audioURL, projectService: projectService, collapsed: true),
            to: collapsedProjectURL
        )
        try projectService.save(
            notationCollapseProject(audioURL: audioURL, projectService: projectService, collapsed: nil),
            to: legacyProjectURL
        )

        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openProject(at: expandedProjectURL)
        XCTAssertFalse(viewModel.isNotationTrackCollapsed)
        XCTAssertFalse(viewModel.isProjectModified)

        await viewModel.openProject(at: collapsedProjectURL)
        XCTAssertTrue(viewModel.isNotationTrackCollapsed)
        XCTAssertFalse(viewModel.isProjectModified)

        await viewModel.openProject(at: legacyProjectURL)
        XCTAssertTrue(viewModel.isNotationTrackCollapsed)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNotationTrackCollapsedStateIsNotUndoable() throws {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.undoManager = undoManager

        viewModel.setNotationTrackCollapsed(false)

        XCTAssertFalse(viewModel.isNotationTrackCollapsed)
        XCTAssertFalse(viewModel.canUndo)

        viewModel.setMainTrackVolume(0.25)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undoLastEdit()

        XCTAssertFalse(viewModel.isNotationTrackCollapsed)
        XCTAssertEqual(viewModel.mainTrackVolume, AppSliderDefaults.mainTrackVolume, accuracy: 0.0001)
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

    @MainActor
    func testSaveProjectForCloseWithoutMediaReturnsFalse() async {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())

        let didSave = await viewModel.saveProjectForClose()

        XCTAssertFalse(didSave)
    }

    @MainActor
    func testSandboxSaveRequiresProjectArtifactFolderAccess() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("sandbox-save.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            formatVersion: 5,
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 0.5,
            notes: [],
            loopStart: 0,
            loopEnd: 0.5,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "sandbox-save",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { true }
        )

        await viewModel.openRecentProject(entry)
        viewModel.setMainTrackVolume(0.2)

        let didSave = await viewModel.saveProjectForClose()

        XCTAssertFalse(didSave)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Project save failed: \(ProjectDocumentError.projectArtifactAccessDenied.localizedDescription)"
        )
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

    private func notationCollapseProject(
        audioURL: URL,
        projectService: ProjectDocumentService,
        collapsed: Bool?
    ) throws -> JammLabProject {
        JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 0.5,
            notes: [],
            loopStart: 0,
            loopEnd: 0.5,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            isNotationTrackCollapsed: collapsed
        )
    }

}
