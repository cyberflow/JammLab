import XCTest
@testable import JammLab

final class ViewModelResetTests: XCTestCase {
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
        viewModel.setNotationTrackCollapsed(false)

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
        XCTAssertNil(viewModel.importedFile)
        XCTAssertEqual(try XCTUnwrap(viewModel.tempoBPM), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(viewModel.beatGridSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(engine.clickSettings.bpm), AppDefaults.defaultTempoBPM, accuracy: 0.0001)
    }
}
