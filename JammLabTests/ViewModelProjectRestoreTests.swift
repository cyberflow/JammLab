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
    func testProjectOpenRestoresAndClampsPlaybackMarkerTime() async throws {
        let audioURL = try temporaryAudioFile(duration: 2)
        let projectURL = temporaryDirectory().appendingPathComponent("playback-marker-open.jammlab")
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
            loopStart: 0,
            loopEnd: 2,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            playbackMarkerTime: 99
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "playback-marker-open",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            videoFollower: videoFollower,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertEqual(viewModel.playbackMarkerTime, 2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 2, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 2, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSaveProjectPersistsPlaybackMarkerTime() async throws {
        let audioURL = try temporaryAudioFile(duration: 2)
        let projectURL = temporaryDirectory().appendingPathComponent("playback-marker-save.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "marker.wav", duration: 2)
        try viewModel.loadImportedAudio(media)

        viewModel.locatePlaybackMarker(to: 1.25)

        XCTAssertTrue(viewModel.isProjectModified)

        let didSave = await viewModel.saveProject(to: projectURL)

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.isProjectModified)
        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(try XCTUnwrap(savedProject.playbackMarkerTime), 1.25, accuracy: 0.0001)
    }

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
