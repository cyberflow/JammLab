import AVFoundation
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
    func testViewModelPlayDoesNotSeekToLoopStart() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        engine.currentTime = 12
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)

        viewModel.setLooping(true)
        viewModel.play()

        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(engine.seekCount, 0)
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

        viewModel.setPlaybackRate(0.5)
        viewModel.play()
        viewModel.seek(to: 10)
        viewModel.pause()
        viewModel.stop()

        XCTAssertEqual(try XCTUnwrap(videoFollower.playbackRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.playRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 0, accuracy: 0.0001)
        XCTAssertTrue(videoFollower.didPause)
        XCTAssertTrue(videoFollower.didStop)
    }

    @MainActor
    func testVideoWindowIsShownOnlyByExplicitCommand() throws {
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
        XCTAssertEqual(videoFollower.loadedVideoURL, videoURL)
        XCTAssertTrue(videoFollower.showWindowEvents.isEmpty)

        viewModel.setPlaybackRate(0.5)
        viewModel.play()

        XCTAssertTrue(videoFollower.showWindowEvents.isEmpty)

        viewModel.showVideoWindow()

        let event = try XCTUnwrap(videoFollower.showWindowEvents.last)
        XCTAssertEqual(event.time, viewModel.currentTime, accuracy: 0.0001)
        XCTAssertTrue(event.isPlaying)
        XCTAssertEqual(event.rate, 0.5, accuracy: 0.0001)

        viewModel.newProject()
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
        XCTAssertFalse(engine.loopEnabled)
        XCTAssertFalse(engine.clickEnabled)
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

    private func temporaryAudioFile(duration: TimeInterval = 0.5) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jammlab-video-window-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount((duration * format.sampleRate).rounded())
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        try file.write(from: buffer)
        return url
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

}
