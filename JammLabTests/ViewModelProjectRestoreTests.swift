import XCTest
@testable import JammLab

final class ViewModelProjectRestoreTests: XCTestCase {
    @MainActor
    func testProjectOpenRestoresLoopClickAndSnapButtonStates() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("toggles.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 2,
            notes: [],
            loopStart: 0.25,
            loopEnd: 1.25,
            isLoopEnabled: true,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            mainTrackVolume: AppSliderDefaults.mainTrackVolume,
            isClickEnabled: true,
            clickVolume: 0.33,
            isSnapEnabled: true
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "toggles",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertTrue(viewModel.isLooping)
        XCTAssertTrue(viewModel.isClickEnabled)
        XCTAssertTrue(viewModel.isSnapEnabled)
        XCTAssertEqual(viewModel.clickVolume, 0.33, accuracy: 0.0001)
        XCTAssertTrue(engine.loopEnabled)
        XCTAssertEqual(engine.loopRegion.start, 0.25, accuracy: 0.0001)
        XCTAssertEqual(engine.loopRegion.end, 1.25, accuracy: 0.0001)
        XCTAssertTrue(engine.clickEnabled)
    }

    @MainActor
    func testLegacyProjectOpenDefaultsLoopClickAndSnapToOff() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("legacy-toggles.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            formatVersion: 4,
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 0.5,
            notes: [],
            loopStart: 0.1,
            loopEnd: 0.4,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "legacy-toggles",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertFalse(viewModel.isLooping)
        XCTAssertFalse(viewModel.isClickEnabled)
        XCTAssertFalse(viewModel.isSnapEnabled)
        XCTAssertEqual(viewModel.playbackMarkerTime, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.upperBound, 0.5, accuracy: 0.0001)
        XCTAssertFalse(engine.loopEnabled)
        XCTAssertFalse(engine.clickEnabled)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testOpenRecentProjectRemovesMissingProjectEntry() async throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "missing-recent.jammlab", contents: "{}")
        let projectDirectory = projectURL.deletingLastPathComponent()
        let projectService = ProjectDocumentService()
        let store = RecentProjectsStore(defaults: defaults)
        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))
        let entry = try XCTUnwrap(store.entries.first)
        try FileManager.default.removeItem(at: projectDirectory)
        let viewModel = AudioPlayerViewModel(
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: store
        )

        await viewModel.openRecentProject(entry)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Could not open recent project: The file doesn’t exist.")
    }
}
