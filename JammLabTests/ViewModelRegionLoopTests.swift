import XCTest
@testable import JammLab

final class ViewModelRegionLoopTests: XCTestCase {
    @MainActor
    func testLocateRegionStartSelectsRegionAndMovesPlaybackMarkerWithoutActivatingLoop() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "region.wav", duration: 6)
        try viewModel.loadImportedAudio(media)
        viewModel.isSnapEnabled = true
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120, firstBeatTime: 0, timeSignature: .fourFour)
        let region = TimecodedNote(kind: .region, time: 2.3, duration: 1.4, title: "Region")
        viewModel.notes = [region]
        viewModel.loopRegion = LoopRegion(start: 0, end: 6)
        viewModel.activeLoopRegionID = nil
        viewModel.markProjectClean()

        viewModel.locateRegionStart(id: region.id)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertNil(viewModel.activeLoopRegionID)
        XCTAssertEqual(viewModel.loopRegion.start, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.loopRegion.end, 6, accuracy: 0.0001)
        XCTAssertEqual(viewModel.playbackMarkerTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testActivateRegionAsLoopWithoutSeekingPreservesPlaybackPosition() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "region.wav", duration: 6)
        try viewModel.loadImportedAudio(media)
        let region = TimecodedNote(kind: .region, time: 2.3, duration: 1.4, title: "Region")
        viewModel.notes = [region]
        viewModel.loopRegion = LoopRegion(start: 0, end: 6)
        viewModel.activeLoopRegionID = nil
        viewModel.setPlaybackMarkerExactly(to: 1.1)
        let initialSeekCount = engine.seekCount
        viewModel.markProjectClean()

        viewModel.activateRegionAsLoop(id: region.id)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertEqual(viewModel.activeLoopRegionID, region.id)
        XCTAssertEqual(viewModel.loopRegion.start, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.loopRegion.end, 3.7, accuracy: 0.0001)
        XCTAssertEqual(engine.loopRegion.start, 2.3, accuracy: 0.0001)
        XCTAssertEqual(engine.loopRegion.end, 3.7, accuracy: 0.0001)
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.1, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 1.1, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 1.1, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, initialSeekCount)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testActivateRegionAsLoopAndMoveMarkerWhenStoppedMovesPlaybackPosition() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            videoFollower: videoFollower
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "region.wav", duration: 6)
        try viewModel.loadImportedAudio(media)
        let region = TimecodedNote(kind: .region, time: 2.3, duration: 1.4, title: "Region")
        viewModel.notes = [region]
        viewModel.setPlaybackMarkerExactly(to: 1.1)
        viewModel.playbackState = .stopped
        viewModel.markProjectClean()

        viewModel.activateRegionAsLoopAndMoveMarker(id: region.id)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertEqual(viewModel.activeLoopRegionID, region.id)
        XCTAssertEqual(viewModel.loopRegion.start, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.loopRegion.end, 3.7, accuracy: 0.0001)
        XCTAssertEqual(viewModel.playbackMarkerTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 2.3, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testActivateRegionAsLoopAndMoveMarkerWhenPausedMovesPlaybackPosition() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            videoFollower: videoFollower
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "region.wav", duration: 6)
        try viewModel.loadImportedAudio(media)
        let region = TimecodedNote(kind: .region, time: 2.3, duration: 1.4, title: "Region")
        viewModel.notes = [region]
        viewModel.setPlaybackMarkerExactly(to: 1.1)
        viewModel.playbackState = .paused
        viewModel.markProjectClean()

        viewModel.activateRegionAsLoopAndMoveMarker(id: region.id)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertEqual(viewModel.activeLoopRegionID, region.id)
        XCTAssertEqual(viewModel.playbackMarkerTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 2.3, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testActivateRegionAsLoopAndMoveMarkerWhilePlayingDoesNotSeekPlayback() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            videoFollower: videoFollower
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "region.wav", duration: 6)
        try viewModel.loadImportedAudio(media)
        let region = TimecodedNote(kind: .region, time: 2.3, duration: 1.4, title: "Region")
        viewModel.notes = [region]
        viewModel.setPlaybackMarkerExactly(to: 1.1)
        let seekCountAfterInitialPosition = engine.seekCount
        let videoSeekCountAfterInitialPosition = videoFollower.seekTimes.count
        viewModel.playbackState = .playing
        engine.isPlaying = true
        engine.currentTime = 4.5
        viewModel.currentTime = 4.5
        viewModel.markProjectClean()

        viewModel.activateRegionAsLoopAndMoveMarker(id: region.id)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertEqual(viewModel.activeLoopRegionID, region.id)
        XCTAssertEqual(viewModel.loopRegion.start, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.loopRegion.end, 3.7, accuracy: 0.0001)
        XCTAssertEqual(viewModel.playbackMarkerTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 4.5, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 4.5, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, seekCountAfterInitialPosition)
        XCTAssertEqual(videoFollower.seekTimes.count, videoSeekCountAfterInitialPosition)
        XCTAssertEqual(viewModel.playbackState, .playing)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testActivateInspectorItemMovesMarkerForRegionsAndKeepsMarkerSeek() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "inspector.wav", duration: 6)
        try viewModel.loadImportedAudio(media)
        let marker = TimecodedNote(time: 4.2, title: "Marker")
        let region = TimecodedNote(kind: .region, time: 2.3, duration: 1.4, title: "Region")
        viewModel.notes = [marker, region]
        viewModel.setPlaybackMarkerExactly(to: 1.1)
        let seekCountAfterInitialPosition = engine.seekCount

        viewModel.activateInspectorItem(region)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertEqual(viewModel.activeLoopRegionID, region.id)
        XCTAssertEqual(viewModel.loopRegion.start, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.loopRegion.end, 3.7, accuracy: 0.0001)
        XCTAssertEqual(viewModel.playbackMarkerTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 2.3, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, seekCountAfterInitialPosition + 1)

        viewModel.activateInspectorItem(marker)

        XCTAssertEqual(viewModel.currentTime, 4.2, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 4.2, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, seekCountAfterInitialPosition + 2)
    }

    @MainActor
    func testEditingActiveRegionDetachesLoopWithoutMovingLoopRange() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "region.wav", duration: 6)
        try viewModel.loadImportedAudio(media)
        let region = TimecodedNote(kind: .region, time: 2, duration: 1, title: "Region")
        viewModel.notes = [region]
        viewModel.activateRegionAsLoop(id: region.id)
        viewModel.markProjectClean()

        viewModel.updateRegionRange(id: region.id, start: 3, end: 4)

        XCTAssertNil(viewModel.activeLoopRegionID)
        XCTAssertEqual(viewModel.loopRegion.start, 2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.loopRegion.end, 3, accuracy: 0.0001)
        XCTAssertEqual(engine.loopRegion.start, 2, accuracy: 0.0001)
        XCTAssertEqual(engine.loopRegion.end, 3, accuracy: 0.0001)
        let updatedRegion = try XCTUnwrap(viewModel.notes.first { $0.id == region.id })
        XCTAssertEqual(updatedRegion.time, 3, accuracy: 0.0001)
        XCTAssertEqual(updatedRegion.regionEndTime, 4, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
    }
}
