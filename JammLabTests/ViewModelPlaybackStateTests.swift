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
    func testLocatingPlaybackMarkerExactlyBypassesSnapAndMarksProjectModified() throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            videoFollower: videoFollower
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "exact-marker.wav", duration: 4)
        try viewModel.loadImportedAudio(media)
        viewModel.isSnapEnabled = true
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120, firstBeatTime: 0, timeSignature: .fourFour)
        viewModel.markProjectClean()

        viewModel.locatePlaybackMarkerExactly(to: 0.74)

        XCTAssertEqual(viewModel.playbackMarkerTime, 0.74, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 0.74, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 0.74, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 0.74, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testLocatingPlaybackMarkerExactlyClampsToTimelineBounds() throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            videoFollower: videoFollower
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "exact-marker-bounds.wav", duration: 4)
        try viewModel.loadImportedAudio(media)

        viewModel.setPlaybackMarkerExactly(to: 2)
        viewModel.markProjectClean()
        viewModel.locatePlaybackMarkerExactly(to: -1)

        XCTAssertEqual(viewModel.playbackMarkerTime, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 0, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 0, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.markProjectClean()
        viewModel.locatePlaybackMarkerExactly(to: 12)

        XCTAssertEqual(viewModel.playbackMarkerTime, 4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 4, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 4, accuracy: 0.0001)
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
    func testPlaybackClockDoesNotStartWhileIdle() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 20
        viewModel.playbackState = .stopped

        viewModel.startPlaybackClock()

        XCTAssertNil(viewModel.clockTask)
    }

    @MainActor
    func testPlayAndPauseOwnPlaybackClockLifecycle() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 20
        viewModel.setPlaybackMarkerExactly(to: 4)

        viewModel.play()

        XCTAssertNotNil(viewModel.clockTask)
        XCTAssertTrue(viewModel.playbackDisplayState.isPlaying)

        viewModel.pause()

        XCTAssertNil(viewModel.clockTask)
        XCTAssertFalse(viewModel.playbackDisplayState.isPlaying)
        XCTAssertEqual(viewModel.playbackDisplayState.sampledTime, 4, accuracy: 0.0001)
    }

    @MainActor
    func testStopCancelsPlaybackClock() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 20
        viewModel.setPlaybackMarkerExactly(to: 3)
        viewModel.play()

        viewModel.stop()

        XCTAssertNil(viewModel.clockTask)
        XCTAssertFalse(viewModel.playbackDisplayState.isPlaying)
        XCTAssertEqual(viewModel.currentTime, 3, accuracy: 0.0001)
    }

}
