import XCTest
@testable import JammLab

final class ViewModelProjectSaveCloseTests: XCTestCase {
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
        let bassPart = NotationPartID.stem(.bass)
        viewModel.notationPartClefs[bassPart] = .treble
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "bass-note",
                partID: bassPart,
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.setNotationClef(.bass, for: bassPart)
        viewModel.setMainTrackVolume(0.2)

        XCTAssertTrue(viewModel.isProjectModified)

        let didSave = await viewModel.saveProjectForClose()

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.isProjectModified)

        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(try XCTUnwrap(savedProject.mainTrackVolume), 0.2, accuracy: 0.0001)
        XCTAssertEqual(savedProject.notationPartClefs[bassPart], .bass)
        XCTAssertEqual(savedProject.notationItems.first?.pitch, NotationPitch(step: .e, octave: 2))
        XCTAssertNotNil(savedProject.artifactRootBookmarkData)
        XCTAssertNil(savedProject.isVideoWindowOpen)

        let restoredViewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )
        await restoredViewModel.openRecentProject(entry)

        XCTAssertEqual(restoredViewModel.notationClef(for: bassPart), .bass)
        XCTAssertEqual(restoredViewModel.notationItems.first?.pitch, NotationPitch(step: .e, octave: 2))
        XCTAssertFalse(restoredViewModel.isProjectModified)
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
}
