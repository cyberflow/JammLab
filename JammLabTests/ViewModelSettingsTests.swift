import XCTest
@testable import JammLab

final class ViewModelSettingsTests: XCTestCase {
    @MainActor
    func testViewModelRestoresClickVolumeFromInjectedSettingsStore() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(0.42, forKey: AppSettingsStore.clickVolumeKey)
        let engine = MockPlaybackEngine()

        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            appSettingsStore: AppSettingsStore(defaults: defaults)
        )

        XCTAssertEqual(viewModel.clickVolume, 0.42, accuracy: 0.0001)
        XCTAssertEqual(engine.clickVolume, 0.42, accuracy: 0.0001)
    }

    @MainActor
    func testViewModelSetTimelineVisibleRangeClampsWithoutAudio() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())

        viewModel.setTimelineVisibleRange(-20...80)

        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 0, accuracy: 0.0001)
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
}
