import XCTest
@testable import JammLab

final class ViewModelTimelineRangePersistenceTests: XCTestCase {
    @MainActor
    func testManualTimelineRangeChangesDirtyStateAndPersistsOnSave() async throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        let projectURL = temporaryDirectory().appendingPathComponent("timeline-range-save.jammlab")
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
        let media = ImportedAudioFile(url: audioURL, displayName: "viewport.wav", duration: 4)
        try viewModel.loadImportedAudio(media)

        viewModel.setTimelineVisibleRange(1...2.5)

        XCTAssertTrue(viewModel.isProjectModified)

        let didSave = await viewModel.saveProject(to: projectURL)

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.isProjectModified)
        let savedProject = try projectService.load(from: projectURL)
        let savedRange = try XCTUnwrap(savedProject.timelineVisibleRange)
        XCTAssertEqual(savedRange.start, 1, accuracy: 0.0001)
        XCTAssertEqual(savedRange.end, 2.5, accuracy: 0.0001)
    }

    @MainActor
    func testProjectOpenRestoresTimelineVisibleRange() async throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        let projectURL = temporaryDirectory().appendingPathComponent("timeline-range-open.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 4,
            notes: [],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            timelineVisibleRange: ProjectTimelineVisibleRange(start: 1, end: 2.5)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "timeline-range-open",
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

        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 1, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 2.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.lowerBound, 1, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.upperBound, 2.5, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testProjectOpenDefaultsInvalidTimelineVisibleRangeToFullDuration() async throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        let projectURL = temporaryDirectory().appendingPathComponent("timeline-range-invalid.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 4,
            notes: [],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            timelineVisibleRange: ProjectTimelineVisibleRange(start: -1, end: 99)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "timeline-range-invalid",
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

        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.upperBound, 4, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }
}
