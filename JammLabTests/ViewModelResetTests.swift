import XCTest
@testable import JammLab

final class ViewModelResetTests: XCTestCase {
    @MainActor
    func testViewModelResetMethodsUseSliderDefaults() throws {
        let engine = MockPlaybackEngine()
        let settingsStore = AppSettingsStore(defaults: try temporaryUserDefaults())
        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            appSettingsStore: settingsStore
        )

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
        XCTAssertEqual(engine.playbackRate, AppSliderDefaults.playbackRate, accuracy: 0.0001)
        XCTAssertEqual(engine.pitchShiftSemitones, AppSliderDefaults.pitchShiftSemitones, accuracy: 0.0001)
        XCTAssertEqual(engine.mainVolume, AppSliderDefaults.mainTrackVolume, accuracy: 0.0001)
        XCTAssertEqual(engine.clickVolume, AppSliderDefaults.clickVolume, accuracy: 0.0001)
    }

    @MainActor
    func testViewModelNewProjectResetsPlaybackControlsAndUnloadsEngine() throws {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let settingsStore = AppSettingsStore(defaults: try temporaryUserDefaults())
        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            appSettingsStore: settingsStore
        )

        viewModel.setPlaybackRate(0.5)
        viewModel.setPitchShift(semitones: 7)
        viewModel.setMainTrackVolume(0.1)
        viewModel.setClickVolume(0.2)
        viewModel.setStemVolume(.vocals, volume: 0.2)
        viewModel.toggleStemMute(.vocals)
        viewModel.toggleSnap()
        viewModel.setLooping(true)
        viewModel.setNotationTrackCollapsed(false)
        viewModel.notationDurationDenominator = 8
        viewModel.notationEntryDurationIsDotted = true

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
        XCTAssertTrue(viewModel.isNotationTrackCollapsed)
        XCTAssertEqual(viewModel.notationDurationDenominator, NotationDuration.defaultDenominator)
        XCTAssertFalse(viewModel.notationDurationIsDotted)
        XCTAssertNil(viewModel.importedFile)
        XCTAssertEqual(try XCTUnwrap(viewModel.tempoBPM), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(viewModel.beatGridSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.clickSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
    }
}
