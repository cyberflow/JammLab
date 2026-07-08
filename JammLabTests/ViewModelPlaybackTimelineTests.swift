import XCTest
@testable import JammLab

final class ViewModelPlaybackTimelineTests: XCTestCase {
    @MainActor
    func testPlaybackClockFollowsZoomedTimelineNearRightEdge() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.isPlaying = true
        engine.currentTime = 18.4
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 100
        viewModel.setTimelineVisibleRange(0...20)
        viewModel.playbackState = .playing

        viewModel.refreshPlaybackPosition()

        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound - viewModel.timelineVisibleRange.lowerBound, 20, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 16.8, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineViewport.xPosition(for: viewModel.currentTime, width: 100), 8, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.upperBound, 20, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testPlaybackFollowDoesNotDirtyOrReplaceUserTimelineRange() throws {
        let audioURL = try temporaryAudioFile(duration: 100)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "follow.wav", duration: 100)
        try viewModel.loadImportedAudio(media)
        viewModel.setTimelineVisibleRange(0...20)
        viewModel.markProjectClean()
        engine.isPlaying = true
        engine.currentTime = 18.4
        viewModel.playbackState = .playing

        viewModel.refreshPlaybackPosition()

        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 16.8, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 36.8, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.upperBound, 20, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testPlaybackClockDoesNotFollowFullTimelineRange() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.isPlaying = true
        engine.currentTime = 95
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 100
        viewModel.setTimelineVisibleRange(0...100)
        viewModel.playbackState = .playing

        viewModel.refreshPlaybackPosition()

        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 100, accuracy: 0.0001)
    }

    @MainActor
    func testStopReturnsZoomedTimelineToPlaybackMarker() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.currentTime = 70
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 100
        viewModel.setPlaybackMarkerExactly(to: 30)
        viewModel.setTimelineVisibleRange(60...80)
        viewModel.playbackState = .playing

        viewModel.stop()

        XCTAssertEqual(viewModel.currentTime, 30, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 30, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound - viewModel.timelineVisibleRange.lowerBound, 20, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 28.4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineViewport.xPosition(for: viewModel.playbackMarkerTime, width: 100), 8, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackAutoStopAtEndReturnsToPlaybackMarker() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.isPlaying = false
        engine.currentTime = 4
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        viewModel.duration = 4
        viewModel.setPlaybackMarkerExactly(to: 1)
        viewModel.setTimelineVisibleRange(2...4)
        engine.currentTime = 4
        viewModel.playbackState = .playing

        viewModel.refreshPlaybackPosition()

        XCTAssertEqual(viewModel.playbackState, .stopped)
        XCTAssertEqual(viewModel.currentTime, 1, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 1, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 0.84, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 2.84, accuracy: 0.0001)
    }
}
