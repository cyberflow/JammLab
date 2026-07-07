import XCTest
@testable import JammLab

final class ViewModelPlaybackStateTests: XCTestCase {
    @MainActor
    func testViewModelLoopingDoesNotSeekPlaybackEngine() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.currentTime = 12
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)

        viewModel.setLooping(true)

        XCTAssertTrue(viewModel.isLooping)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, 0)
        XCTAssertTrue(engine.loopEnabled)
    }

    @MainActor
    func testViewModelPlayStartsFromPlaybackMarkerNotLoopStart() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.currentTime = 12
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 20
        viewModel.setPlaybackMarkerExactly(to: 4)

        viewModel.setLooping(true)
        viewModel.play()

        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 4, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, 2)
    }

    @MainActor
    func testViewModelStopReturnsToPlaybackMarker() throws {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.currentTime = 12
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        viewModel.duration = 20
        viewModel.setPlaybackMarkerExactly(to: 3)

        viewModel.play()
        engine.currentTime = 12
        viewModel.stop()

        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 3, accuracy: 0.0001)
    }

    @MainActor
    func testViewModelPauseMovesPlaybackMarkerToPausedPosition() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.currentTime = 12
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 20
        viewModel.setPlaybackMarkerExactly(to: 3)
        engine.currentTime = 12

        viewModel.pause()

        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(viewModel.playbackMarkerTime, 12, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 12, accuracy: 0.0001)
    }

    @MainActor
    func testLocatingPlaybackMarkerAppliesSnapAndMarksProjectModified() throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "marker.wav", duration: 4)
        try viewModel.loadImportedAudio(media)
        viewModel.isSnapEnabled = true
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120, firstBeatTime: 0, timeSignature: .fourFour)
        viewModel.markProjectClean()

        viewModel.locatePlaybackMarker(to: 0.74)

        XCTAssertEqual(viewModel.playbackMarkerTime, 0.5, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 0.5, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testPlaybackClockMovementDoesNotMarkProjectModified() throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "clock.wav", duration: 4)
        try viewModel.loadImportedAudio(media)
        viewModel.markProjectClean()

        engine.currentTime = 1.25
        viewModel.refreshPlaybackPosition()

        XCTAssertEqual(viewModel.currentTime, 1.25, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }

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
