import XCTest
@testable import JammLab

final class ViewModelProjectPlaybackMarkerTests: XCTestCase {
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
}
