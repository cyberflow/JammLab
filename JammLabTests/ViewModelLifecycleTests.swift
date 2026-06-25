import XCTest
@testable import JammLab

final class ViewModelLifecycleTests: XCTestCase {
    @MainActor
    func testViewModelResetMethodsUseSliderDefaults() throws {
        let clickVolumeKey = "metronome.volume"
        let originalClickVolumeValue = UserDefaults.standard.object(forKey: clickVolumeKey)
        defer {
            if let originalClickVolumeValue {
                UserDefaults.standard.set(originalClickVolumeValue, forKey: clickVolumeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: clickVolumeKey)
            }
        }

        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)

        XCTAssertEqual(try XCTUnwrap(viewModel.tempoBPM), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(viewModel.beatGridSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.clickSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)

        viewModel.setPlaybackRate(0.5)
        viewModel.setPitchShift(semitones: 7)
        viewModel.setMainTrackVolume(0.1)
        viewModel.setStemVolume(.vocals, volume: 0.2)
        viewModel.setStemVolume(.drums, volume: 0.4)
        viewModel.toggleStemMute(.vocals)
        viewModel.toggleStemSolo(.drums)
        viewModel.setClickVolume(0.2)

        viewModel.resetPlaybackRateToDefault()
        viewModel.resetPitchShiftToDefault()
        viewModel.resetMainTrackVolumeToDefault()
        viewModel.resetStemVolumeToDefault(.vocals)
        viewModel.resetClickVolumeToDefault()

        XCTAssertEqual(viewModel.playbackRate, AppSliderDefaults.playbackRate, accuracy: 0.0001)
        XCTAssertEqual(viewModel.pitchShiftSemitones, AppSliderDefaults.pitchShiftSemitones, accuracy: 0.0001)
        XCTAssertEqual(viewModel.mainTrackVolume, AppSliderDefaults.mainTrackVolume, accuracy: 0.0001)
        XCTAssertEqual(viewModel.clickVolume, AppSliderDefaults.clickVolume, accuracy: 0.0001)
        XCTAssertEqual(viewModel.stemMixState.item(for: .vocals).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertEqual(viewModel.stemMixState.item(for: .drums).volume, 0.4, accuracy: 0.0001)
        XCTAssertTrue(viewModel.stemMixState.item(for: .vocals).isMuted)
        XCTAssertTrue(viewModel.stemMixState.item(for: .drums).isSoloed)
        if let originalClickVolumeValue {
            XCTAssertEqual(UserDefaults.standard.object(forKey: clickVolumeKey) as? Float, originalClickVolumeValue as? Float)
        } else {
            XCTAssertNil(UserDefaults.standard.object(forKey: clickVolumeKey))
        }
        XCTAssertEqual(engine.playbackRate, AppSliderDefaults.playbackRate, accuracy: 0.0001)
        XCTAssertEqual(engine.pitchShiftSemitones, AppSliderDefaults.pitchShiftSemitones, accuracy: 0.0001)
        XCTAssertEqual(engine.mainVolume, AppSliderDefaults.mainTrackVolume, accuracy: 0.0001)
        XCTAssertEqual(engine.clickVolume, AppSliderDefaults.clickVolume, accuracy: 0.0001)
    }

    @MainActor
    func testViewModelNewProjectResetsPlaybackControlsAndUnloadsEngine() throws {
        let clickVolumeKey = "metronome.volume"
        let originalClickVolumeValue = UserDefaults.standard.object(forKey: clickVolumeKey)
        defer {
            if let originalClickVolumeValue {
                UserDefaults.standard.set(originalClickVolumeValue, forKey: clickVolumeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: clickVolumeKey)
            }
        }

        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)

        viewModel.setPlaybackRate(0.5)
        viewModel.setPitchShift(semitones: 7)
        viewModel.setMainTrackVolume(0.1)
        viewModel.setClickVolume(0.2)
        viewModel.setStemVolume(.vocals, volume: 0.2)
        viewModel.toggleStemMute(.vocals)
        viewModel.toggleSnap()
        viewModel.setLooping(true)

        viewModel.newProject()

        XCTAssertEqual(engine.unloadCount, 1)
        XCTAssertFalse(engine.clickEnabled)
        XCTAssertEqual(viewModel.playbackRate, AppSliderDefaults.playbackRate, accuracy: 0.0001)
        XCTAssertEqual(viewModel.pitchShiftSemitones, AppSliderDefaults.pitchShiftSemitones, accuracy: 0.0001)
        XCTAssertEqual(viewModel.mainTrackVolume, AppSliderDefaults.mainTrackVolume, accuracy: 0.0001)
        XCTAssertEqual(viewModel.stemMixState.item(for: .vocals).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertFalse(viewModel.stemMixState.item(for: .vocals).isMuted)
        XCTAssertFalse(viewModel.isSnapEnabled)
        XCTAssertFalse(viewModel.isLooping)
        XCTAssertNil(viewModel.importedFile)
        XCTAssertEqual(try XCTUnwrap(viewModel.tempoBPM), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(viewModel.beatGridSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.clickSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
    }

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

    @MainActor
    func testViewModelTogglePlaybackModeStaysOriginalWhenStemsUnavailable() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())

        viewModel.togglePlaybackMode()

        XCTAssertEqual(viewModel.playbackMode, .original)
    }

    @MainActor
    func testViewModelSetPlaybackModeStaysOriginalWhenStemsUnavailable() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())

        viewModel.setPlaybackMode(.stems)

        XCTAssertEqual(viewModel.playbackMode, .original)
    }

    @MainActor
    func testRegisterStemMetadataActivatesStemPlaybackWhenRequested() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12

        viewModel.registerStemMetadata(testStemMetadata(), activatePlayback: true)

        XCTAssertEqual(viewModel.playbackMode, .stems)
        XCTAssertEqual(viewModel.stemFiles.map(\.type), StemSeparationMethod.fourStem.stemTypes)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(engine.mixState.item(for: .vocals).isAvailable)
        XCTAssertEqual(viewModel.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
    }

    @MainActor
    func testRegisterStemMetadataPreservesPlayingPositionWhenActivatingStems() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12
        viewModel.playbackMarkerTime = 2
        viewModel.playbackState = .playing
        engine.isLoaded = true
        engine.isPlaying = true
        engine.currentTime = 12

        viewModel.registerStemMetadata(testStemMetadata(), activatePlayback: true)

        XCTAssertEqual(viewModel.playbackMode, .stems)
        XCTAssertEqual(viewModel.playbackState, .playing)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(viewModel.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(viewModel.playbackMarkerTime, 2, accuracy: 0.0001)
    }

    @MainActor
    func testRegisterStemMetadataDoesNotActivateStemPlaybackByDefault() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12

        viewModel.registerStemMetadata(testStemMetadata())

        XCTAssertEqual(viewModel.playbackMode, .original)
        XCTAssertEqual(viewModel.stemFiles.map(\.type), StemSeparationMethod.fourStem.stemTypes)
        XCTAssertFalse(engine.isLoaded)
    }

    @MainActor
    func testRegisterStemMetadataLoadsPlaybackWhenProjectRestoresStemMode() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12
        viewModel.playbackMode = .stems

        viewModel.registerStemMetadata(testStemMetadata())

        XCTAssertEqual(viewModel.playbackMode, .stems)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(engine.mixState.item(for: .drums).isAvailable)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
    }

    @MainActor
    func testViewModelSetTimelineVisibleRangeClampsWithoutAudio() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())

        viewModel.setTimelineVisibleRange(-20...80)

        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 0, accuracy: 0.0001)
    }

    @MainActor
    func testViewModelForwardsTransportCommandsToVideoFollower() throws {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        viewModel.duration = 20

        viewModel.setPlaybackRate(0.5)
        viewModel.play()
        viewModel.seek(to: 10)
        viewModel.pause()
        viewModel.stop()

        XCTAssertEqual(try XCTUnwrap(videoFollower.playbackRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.playRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 10, accuracy: 0.0001)
        XCTAssertTrue(videoFollower.didPause)
        XCTAssertTrue(videoFollower.didStop)
    }

    @MainActor
    func testVideoImportAutoShowsVideoWindowAndStartsClean() throws {
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let videoURL = URL(fileURLWithPath: "/tmp/lesson.mov")
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)

        XCTAssertTrue(viewModel.canShowVideoWindow)
        XCTAssertTrue(viewModel.canToggleVideoWindow)
        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertEqual(videoFollower.loadedVideoURL, videoURL)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
        XCTAssertFalse(viewModel.isProjectModified)

        let importEvent = try XCTUnwrap(videoFollower.showWindowEvents.last)
        XCTAssertEqual(importEvent.time, 0, accuracy: 0.0001)
        XCTAssertFalse(importEvent.isPlaying)
        XCTAssertEqual(importEvent.rate, AppSliderDefaults.playbackRate, accuracy: 0.0001)

        viewModel.setPlaybackRate(0.5)
        viewModel.play()

        viewModel.showVideoWindow()

        let event = try XCTUnwrap(videoFollower.showWindowEvents.last)
        XCTAssertEqual(event.time, viewModel.currentTime, accuracy: 0.0001)
        XCTAssertTrue(event.isPlaying)
        XCTAssertEqual(event.rate, 0.5, accuracy: 0.0001)

        viewModel.newProject()
    }

    @MainActor
    func testAudioImportDoesNotShowVideoWindow() throws {
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let media = ImportedAudioFile(url: audioURL, displayName: "lesson.wav", duration: 0.5)

        try viewModel.loadImportedAudio(media)

        XCTAssertFalse(viewModel.canShowVideoWindow)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertTrue(videoFollower.showWindowEvents.isEmpty)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testToggleVideoWindowIsNoOpWithoutVideoMedia() {
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(videoFollower: videoFollower)

        XCTAssertFalse(viewModel.canToggleVideoWindow)

        viewModel.toggleVideoWindow()

        XCTAssertTrue(videoFollower.toggleWindowEvents.isEmpty)
    }

    @MainActor
    func testToggleVideoWindowForwardsCurrentPlaybackStateForVideoMedia() throws {
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let videoURL = URL(fileURLWithPath: "/tmp/lesson.mov")
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)
        videoFollower.closeWindow()
        viewModel.markProjectClean()
        viewModel.setPlaybackRate(0.5)
        viewModel.play()
        viewModel.toggleVideoWindow()

        let event = try XCTUnwrap(videoFollower.toggleWindowEvents.last)
        XCTAssertEqual(event.time, viewModel.currentTime, accuracy: 0.0001)
        XCTAssertTrue(event.isPlaying)
        XCTAssertEqual(event.rate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
    }

    @MainActor
    func testVideoWindowOpenCloseUpdatesProjectModifiedState() throws {
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: URL(fileURLWithPath: "/tmp/lesson.mov"),
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)

        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertFalse(viewModel.isProjectModified)

        videoFollower.closeWindow()

        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.showVideoWindow()

        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNewProjectUnloadsPreparedVideoFollower() throws {
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: URL(fileURLWithPath: "/tmp/lesson.mov"),
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)
        viewModel.newProject()

        XCTAssertTrue(videoFollower.didUnload)
        XCTAssertFalse(viewModel.canShowVideoWindow)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
    }

    @MainActor
    func testViewModelForwardsClickSoundSettingsUpdatesToPlaybackEngine() throws {
        let defaults = try temporaryUserDefaults()
        let settingsStore = JammLab.AppSettingsStore(defaults: defaults)
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, appSettingsStore: settingsStore)
        _ = viewModel

        XCTAssertEqual(engine.clickSoundSettings, .defaultValue)

        let custom = JammLab.ClickSoundSettings(
            accentFrequencyHz: 2_400,
            regularFrequencyHz: 1_000,
            accentLengthMs: 44,
            regularLengthMs: 18
        )
        settingsStore.updateClickSoundSettings(custom)

        let expectation = expectation(description: "click sound settings forwarded")
        DispatchQueue.main.async {
            XCTAssertEqual(engine.clickSoundSettings, custom)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    @MainActor
    func testViewModelAppliesAndForwardsAudioOutputDeviceSettings() throws {
        let defaults = try temporaryUserDefaults()
        let savedSettings = AudioDeviceSettings(inputDeviceUID: "input-1", outputDeviceUID: "output-1")
        defaults.set(try JSONEncoder().encode(savedSettings), forKey: AppSettingsStore.audioDeviceSettingsKey)

        let settingsStore = JammLab.AppSettingsStore(defaults: defaults)
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, appSettingsStore: settingsStore)
        _ = viewModel

        XCTAssertEqual(engine.audioOutputDeviceUID, "output-1")

        settingsStore.updateAudioOutputDeviceUID("output-2")

        let outputExpectation = expectation(description: "output device setting forwarded")
        DispatchQueue.main.async {
            XCTAssertEqual(engine.audioOutputDeviceUID, "output-2")
            XCTAssertEqual(Array(engine.audioOutputDeviceUIDs.suffix(2)), ["output-1", "output-2"])
            outputExpectation.fulfill()
        }
        wait(for: [outputExpectation], timeout: 1)

        settingsStore.updateAudioInputDeviceUID("input-2")

        let inputExpectation = expectation(description: "input device setting not forwarded to playback")
        DispatchQueue.main.async {
            XCTAssertEqual(engine.audioOutputDeviceUID, "output-2")
            XCTAssertEqual(Array(engine.audioOutputDeviceUIDs.suffix(2)), ["output-1", "output-2"])
            inputExpectation.fulfill()
        }
        wait(for: [inputExpectation], timeout: 1)
    }

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

    @MainActor
    func testOpeningVideoProjectWithoutLocalAudioDoesNotCreateProjectMediaDirectory() async throws {
        let missingVideoURL = try temporaryFile(name: "missing-video.mov", contents: "video")
        let projectDirectory = temporaryDirectory()
        let projectURL = projectDirectory.appendingPathComponent("video-readonly.jammlab")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: missingVideoURL)
            try? FileManager.default.removeItem(at: projectDirectory)
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: missingVideoURL),
            audioDisplayName: "lesson.mov",
            audioDuration: 0.5,
            mediaKind: .video,
            notes: [],
            loopStart: 0,
            loopEnd: 0.5,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        try FileManager.default.removeItem(at: missingVideoURL)
        let entry = RecentProjectEntry(
            displayName: "video-readonly",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let artifactStore = ProjectArtifactStore()
        let viewModel = AudioPlayerViewModel(
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            projectArtifactStore: artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.importedFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactStore.mediaDirectory(for: projectURL).path))
    }

    @MainActor
    func testImportedAudioStartsCleanAndPersistedEditMarksProjectModified() throws {
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "loop.wav", duration: 0.5)

        try viewModel.loadImportedAudio(media)

        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertEqual(viewModel.windowTitle, "loop.wav - JammLab")

        viewModel.setMainTrackVolume(0.2)

        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertEqual(viewModel.windowTitle, "loop.wav [modified] - JammLab")
    }

    @MainActor
    func testUndoRedoLoopingUpdatesModifiedState() throws {
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "loop.wav", duration: 0.5)
        try viewModel.loadImportedAudio(media)
        viewModel.undoManager = undoManager

        viewModel.setLooping(true)

        XCTAssertTrue(viewModel.isLooping)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        XCTAssertFalse(viewModel.isLooping)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        XCTAssertTrue(viewModel.isLooping)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testTimeSignatureChangeUpdatesClickSettingsModifiedStateAndUndo() throws {
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let undoManager = UndoManager()
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "meter.wav", duration: 2)
        try viewModel.loadImportedAudio(media)
        viewModel.undoManager = undoManager

        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertEqual(viewModel.beatGridSettings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
        XCTAssertEqual(engine.clickSettings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.beatGridSettings.timeSignature, .fourFour)
        XCTAssertEqual(engine.clickSettings.timeSignature, .fourFour)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        XCTAssertEqual(viewModel.beatGridSettings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testAddingTempoTimeSignatureMarkerUpdatesPlaybackTempoMap() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 60, beatsPerBar: 3)

        let marker = try XCTUnwrap(viewModel.notes.first)
        let payload = try XCTUnwrap(marker.tempoTimeSignaturePayload)
        let tempoMap = try XCTUnwrap(engine.tempoMap)

        XCTAssertTrue(marker.isTempoTimeSignatureMarker)
        XCTAssertEqual(marker.title, "60 BPM · 3/4")
        XCTAssertEqual(try XCTUnwrap(payload.bpm), 60, accuracy: 0.0001)
        XCTAssertEqual(payload.beatsPerBar, 3)
        XCTAssertFalse(payload.setsNewFirstBeat)
        XCTAssertEqual(tempoMap.segments.count, 2)
        XCTAssertEqual(tempoMap.segments[1].startTime, 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(tempoMap.segments[1].settings.bpm), 60, accuracy: 0.0001)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 2)
        XCTAssertEqual(tempoMap.segments[1].settings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
    }

    @MainActor
    func testAddingNewFirstBeatOnlyMarkerUpdatesPlaybackTempoMap() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(
            at: 2,
            bpm: 120,
            beatsPerBar: 4,
            setsNewFirstBeat: true
        )

        let marker = try XCTUnwrap(viewModel.notes.first)
        let payload = try XCTUnwrap(marker.tempoTimeSignaturePayload)
        let tempoMap = try XCTUnwrap(engine.tempoMap)

        XCTAssertEqual(marker.title, "New First Beat")
        XCTAssertTrue(payload.setsNewFirstBeat)
        XCTAssertNil(payload.bpm)
        XCTAssertNil(payload.beatsPerBar)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 1)
    }

    @MainActor
    func testEditingTempoTimeSignatureMarkerBackToEffectiveSettingsRemovesNoOpMarker() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 60, beatsPerBar: 3)
        let marker = try XCTUnwrap(viewModel.notes.first)

        viewModel.updateTempoTimeSignatureMarker(id: marker.id, bpm: 120, beatsPerBar: 4)

        let updatedTempoMap = try XCTUnwrap(engine.tempoMap)
        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertEqual(updatedTempoMap.segments.count, 1)
        XCTAssertEqual(try XCTUnwrap(updatedTempoMap.segments.first?.settings.bpm), 120, accuracy: 0.0001)
    }

    @MainActor
    func testEditingTempoTimeSignatureMarkerUpdatesNewFirstBeatFlag() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 60, beatsPerBar: 3)
        let marker = try XCTUnwrap(viewModel.notes.first)

        viewModel.updateTempoTimeSignatureMarker(
            id: marker.id,
            bpm: 60,
            beatsPerBar: 3,
            setsNewFirstBeat: true
        )

        let updatedMarker = try XCTUnwrap(viewModel.notes.first)
        let payload = try XCTUnwrap(updatedMarker.tempoTimeSignaturePayload)
        let tempoMap = try XCTUnwrap(engine.tempoMap)
        XCTAssertTrue(payload.setsNewFirstBeat)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 1)
    }

    @MainActor
    func testSelectionOnlyRegionFocusDoesNotMarkProjectModified() async throws {
        let audioURL = try temporaryAudioFile(duration: 2)
        let projectURL = temporaryDirectory().appendingPathComponent("selection.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let region = TimecodedNote(kind: .region, time: 0.25, duration: 0.5, title: "Region")
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 2,
            notes: [region],
            loopStart: 0,
            loopEnd: 2,
            isLoopEnabled: false,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "selection",
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

        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.focusRegion(id: region.id)

        XCTAssertEqual(viewModel.selectedRegionID, region.id)
        XCTAssertFalse(viewModel.isProjectModified)
    }

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
    func testActivateInspectorItemUsesNoSeekForRegionsAndKeepsMarkerSeek() throws {
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
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.1, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 1.1, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 1.1, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, seekCountAfterInitialPosition)

        viewModel.activateInspectorItem(marker)

        XCTAssertEqual(viewModel.currentTime, 4.2, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 4.2, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, seekCountAfterInitialPosition + 1)
    }

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
        viewModel.setMainTrackVolume(0.2)

        XCTAssertTrue(viewModel.isProjectModified)

        let didSave = await viewModel.saveProjectForClose()

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.isProjectModified)

        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(try XCTUnwrap(savedProject.mainTrackVolume), 0.2, accuracy: 0.0001)
        XCTAssertNotNil(savedProject.artifactRootBookmarkData)
        XCTAssertNil(savedProject.isVideoWindowOpen)
    }

    @MainActor
    func testSaveProjectPersistsVideoWindowOpenState() async throws {
        let audioURL = try temporaryAudioFile()
        let videoURL = try temporaryFile(name: "lesson.mov", contents: "video")
        let projectURL = temporaryDirectory().appendingPathComponent("video-window-save.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: videoURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)

        let didSaveOpenState = await viewModel.saveProject(to: projectURL)
        XCTAssertTrue(didSaveOpenState)
        XCTAssertEqual(try projectService.load(from: projectURL).isVideoWindowOpen, true)
        XCTAssertFalse(viewModel.isProjectModified)

        videoFollower.closeWindow()

        XCTAssertTrue(viewModel.isProjectModified)
        let didSaveClosedState = await viewModel.saveProject(to: projectURL)
        XCTAssertTrue(didSaveClosedState)
        XCTAssertEqual(try projectService.load(from: projectURL).isVideoWindowOpen, false)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testOpenProjectRestoresSavedVideoWindowOpenState() async throws {
        let fixture = try makeVideoProjectFixture(
            name: "video-window-open",
            isVideoWindowOpen: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: fixture.projectService,
            projectArtifactStore: fixture.artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openProject(at: fixture.projectURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(videoFollower.loadedVideoURL, fixture.videoURL)
        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testOpenProjectClosesVideoWindowWhenSavedStateIsClosed() async throws {
        let fixture = try makeVideoProjectFixture(
            name: "video-window-closed",
            isVideoWindowOpen: false
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: fixture.projectService,
            projectArtifactStore: fixture.artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )
        videoFollower.showWindow(at: 0, isPlaying: false, rate: 1)

        await viewModel.openProject(at: fixture.projectURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertFalse(videoFollower.isWindowOpen)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
        XCTAssertGreaterThanOrEqual(videoFollower.closeWindowCount, 1)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testOpenLegacyVideoProjectWithoutWindowStateKeepsVideoWindowClosed() async throws {
        let fixture = try makeVideoProjectFixture(
            name: "video-window-legacy",
            isVideoWindowOpen: nil
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            videoFollower: videoFollower,
            projectService: fixture.projectService,
            projectArtifactStore: fixture.artifactStore,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openProject(at: fixture.projectURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertFalse(videoFollower.isWindowOpen)
        XCTAssertTrue(videoFollower.showWindowEvents.isEmpty)
        XCTAssertFalse(viewModel.isProjectModified)
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

    private struct VideoProjectFixture {
        let directory: URL
        let projectURL: URL
        let videoURL: URL
        let projectService: ProjectDocumentService
        let artifactStore: ProjectArtifactStore
    }

    private func makeVideoProjectFixture(
        name: String,
        isVideoWindowOpen: Bool?
    ) throws -> VideoProjectFixture {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let projectURL = directory.appendingPathComponent("\(name).jammlab")
        let videoURL = try temporaryFile(in: directory, name: "\(name).mov", contents: "video")
        let localAudioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: localAudioURL) }

        let artifactStore = ProjectArtifactStore()
        try FileManager.default.createDirectory(
            at: artifactStore.mediaDirectory(for: projectURL),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: localAudioURL,
            to: artifactStore.videoAudioURL(for: projectURL)
        )

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: videoURL),
            audioDisplayName: videoURL.lastPathComponent,
            audioDuration: 0.5,
            mediaKind: .video,
            notes: [],
            loopStart: 0,
            loopEnd: 0.5,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            isVideoWindowOpen: isVideoWindowOpen
        )
        try projectService.save(project, to: projectURL)

        return VideoProjectFixture(
            directory: directory,
            projectURL: projectURL,
            videoURL: videoURL,
            projectService: projectService,
            artifactStore: artifactStore
        )
    }

    @MainActor
    func testProjectEditableStateRestoreAppliesEngineBackedSettings() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        let noteID = TimecodedNote.ID()
        let regionID = TimecodedNote.ID()
        let notes = [
            TimecodedNote(id: noteID, time: 1, title: "Marker A"),
            TimecodedNote(id: regionID, kind: .region, time: 2, duration: 3, title: "Region A", color: .regionGreen)
        ]
        var mix = StemMixState()
        mix.update(.vocals) {
            $0.volume = 0.2
            $0.isMuted = true
        }
        let beatGrid = BeatGridSettings(bpm: 140, firstBeatTime: 0.5, timeSignature: .fourFour)
        let state = ProjectEditableState(
            notes: notes,
            selectedRegionID: regionID,
            activeLoopRegionID: regionID,
            loopRegion: LoopRegion(start: 2, end: 5),
            isLooping: true,
            tempoBPM: 140,
            beatGridSettings: beatGrid,
            playbackRate: 0.5,
            pitchShiftSemitones: -3,
            mainTrackVolume: 0.4,
            stemMixState: mix,
            playbackMode: .original,
            isClickEnabled: true,
            clickVolume: 0.25,
            isSnapEnabled: true
        )

        viewModel.restoreEditableState(state)

        XCTAssertEqual(viewModel.notes.count, 2)
        XCTAssertEqual(viewModel.selectedRegionID, regionID)
        XCTAssertEqual(viewModel.activeLoopRegionID, regionID)
        XCTAssertTrue(viewModel.isLooping)
        XCTAssertEqual(viewModel.playbackRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.pitchShiftSemitones, -3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.mainTrackVolume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.clickVolume, 0.25, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isClickEnabled)
        XCTAssertTrue(viewModel.isSnapEnabled)
        XCTAssertEqual(engine.playbackRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(engine.pitchShiftSemitones, -3, accuracy: 0.0001)
        XCTAssertEqual(engine.mainVolume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(engine.clickVolume, 0.25, accuracy: 0.0001)
        XCTAssertTrue(engine.clickEnabled)
        XCTAssertEqual(try XCTUnwrap(engine.clickSettings.bpm), 140, accuracy: 0.0001)
        XCTAssertTrue(viewModel.stemMixState.item(for: .vocals).isMuted)
    }

    @MainActor
    func testUndoRestoresStemMuteAndRedoReappliesIt() {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.undoManager = undoManager

        viewModel.toggleStemMute(.vocals)

        XCTAssertTrue(viewModel.stemMixState.item(for: .vocals).isMuted)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undoLastEdit()

        XCTAssertFalse(viewModel.stemMixState.item(for: .vocals).isMuted)
        XCTAssertTrue(viewModel.canRedo)

        viewModel.redoLastEdit()

        XCTAssertTrue(viewModel.stemMixState.item(for: .vocals).isMuted)
    }

    @MainActor
    func testUndoRestoresNoteUpdateOrderAndTitle() {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        let markerA = TimecodedNote(time: 10, title: "A")
        let markerB = TimecodedNote(time: 2, title: "B")
        let state = ProjectEditableState(
            notes: [markerA, markerB],
            selectedRegionID: nil,
            activeLoopRegionID: nil,
            loopRegion: .empty,
            isLooping: false,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            mainTrackVolume: AppSliderDefaults.mainTrackVolume,
            stemMixState: StemMixState(),
            playbackMode: .original,
            isClickEnabled: false,
            clickVolume: AppSliderDefaults.clickVolume,
            isSnapEnabled: false
        )
        viewModel.restoreEditableState(state)
        viewModel.undoManager = undoManager

        viewModel.updateNoteTitle(id: markerA.id, title: "Renamed")

        XCTAssertEqual(viewModel.notes.map(\.title), ["Renamed", "B"])

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.notes.map(\.title), ["A", "B"])
    }

    @MainActor
    func testViewModelUpdatesPresetAndCustomNoteColors() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        let marker = TimecodedNote(time: 2, title: "A", color: .markerBlue, customColorHex: "#123456")
        let state = ProjectEditableState(
            notes: [marker],
            selectedRegionID: nil,
            activeLoopRegionID: nil,
            loopRegion: .empty,
            isLooping: false,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            mainTrackVolume: AppSliderDefaults.mainTrackVolume,
            stemMixState: StemMixState(),
            playbackMode: .original,
            isClickEnabled: false,
            clickVolume: AppSliderDefaults.clickVolume,
            isSnapEnabled: false
        )
        viewModel.restoreEditableState(state)

        viewModel.updateNoteCustomColor(id: marker.id, hex: "abcdef")

        XCTAssertEqual(viewModel.notes.first?.customColorHex, "#ABCDEF")
        XCTAssertEqual(viewModel.notes.first?.resolvedColorHex, "#ABCDEF")

        viewModel.updateNoteColor(id: marker.id, color: .markerOrange)

        XCTAssertEqual(viewModel.notes.first?.color, .markerOrange)
        XCTAssertNil(viewModel.notes.first?.customColorHex)
        XCTAssertEqual(viewModel.notes.first?.resolvedColorHex, MarkerColor.markerOrange.defaultHex)
    }

    private func testStemMetadata() -> StemCacheMetadata {
        StemCacheMetadata(
            cacheKey: "test-cache",
            sourceFingerprint: StemSourceFingerprint(path: "/tmp/song.wav", fileSize: 42, modificationTime: 10),
            backendIdentifier: "test-backend",
            separationMethodID: StemSeparationMethod.fourStem.id,
            modelName: StemSeparationMethod.fourStem.modelName,
            settingsVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            stems: StemSeparationMethod.fourStem.stemTypes.map { type in
                StemFile(
                    type: type,
                    url: URL(fileURLWithPath: "/tmp/\(type.canonicalStemFilename)"),
                    displayName: type.title
                )
            }
        )
    }

}
