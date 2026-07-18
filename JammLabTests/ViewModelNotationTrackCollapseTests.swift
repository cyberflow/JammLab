import XCTest
@testable import JammLab

final class ViewModelNotationTrackCollapseTests: XCTestCase {
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
    func testProjectSaveAndOpenPreservesStemNotationPartState() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("stem-notation-state.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let makeViewModel: () throws -> AudioPlayerViewModel = {
            AudioPlayerViewModel(
                analyzer: MockAnalyzer(),
                peakformProvider: MockPeakformProvider(),
                playbackEngine: MockPlaybackEngine(),
                projectService: projectService,
                recentProjectsStore: RecentProjectsStore(defaults: try self.temporaryUserDefaults()),
                isSandboxed: { false }
            )
        }
        let savingViewModel = try makeViewModel()
        try savingViewModel.loadImportedAudio(
            ImportedAudioFile(url: audioURL, displayName: "notation.wav", duration: 0.5)
        )
        savingViewModel.notationItems = [
            NotationMeasureItem(
                id: "bass-note",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        savingViewModel.toggleNotationWindowPartVisibility(.stem(.bass))
        savingViewModel.setStemNotationTrackCollapsed(.bass, isCollapsed: false)
        savingViewModel.toggleStemNoteDisplayMode(.bass)

        let didSave = await savingViewModel.saveProject(to: projectURL)
        XCTAssertTrue(didSave)
        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(savedProject.visibleNotationPartIDs, [.main, .stem(.bass)])
        XCTAssertEqual(savedProject.stemNotationTrackCollapsed[.bass], false)
        XCTAssertEqual(savedProject.stemNoteDisplayModes[.bass], .midi)

        let restoredViewModel = try makeViewModel()
        await restoredViewModel.openProject(at: projectURL)

        XCTAssertEqual(restoredViewModel.visibleNotationPartIDs, [.main, .stem(.bass)])
        XCTAssertFalse(restoredViewModel.isStemNotationTrackCollapsed(.bass))
        XCTAssertEqual(restoredViewModel.stemNoteDisplayMode(for: .bass), .midi)
        XCTAssertEqual(restoredViewModel.notationItems.first?.partID, .stem(.bass))
        XCTAssertFalse(restoredViewModel.isProjectModified)
    }

    @MainActor
    func testStemMIDIDisplayModeExpandsLaneAndIsNotUndoable() {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.undoManager = undoManager

        XCTAssertEqual(viewModel.stemNoteDisplayMode(for: .bass), .notation)
        XCTAssertTrue(viewModel.isStemNotationTrackCollapsed(.bass))

        viewModel.toggleStemNoteDisplayMode(.bass)

        XCTAssertEqual(viewModel.stemNoteDisplayMode(for: .bass), .midi)
        XCTAssertFalse(viewModel.isStemNotationTrackCollapsed(.bass))
        XCTAssertFalse(viewModel.canUndo)

        viewModel.setMainTrackVolume(0.25)
        XCTAssertTrue(viewModel.canUndo)
        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.stemNoteDisplayMode(for: .bass), .midi)
        XCTAssertFalse(viewModel.isStemNotationTrackCollapsed(.bass))
    }

    @MainActor
    func testUndoCreatedBeforeMIDIToggleDoesNotRecollapseLane() {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.undoManager = undoManager

        viewModel.setMainTrackVolume(0.25)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.toggleStemNoteDisplayMode(.bass)
        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.stemNoteDisplayMode(for: .bass), .midi)
        XCTAssertFalse(viewModel.isStemNotationTrackCollapsed(.bass))
        XCTAssertEqual(viewModel.mainTrackVolume, AppSliderDefaults.mainTrackVolume, accuracy: 0.0001)
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
