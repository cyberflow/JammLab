import CoreAudio
import XCTest
@testable import JammLab

final class TunerInputServiceSignalTests: XCTestCase {
    @MainActor
    func testTunerInputServicePublishesSignalLevelWhenPitchIsUnavailable() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        engine.debugEvents = [
            .deviceSwitch(status: noErr),
            .format(sampleRate: 44_100, channelCount: 1, commonFormat: .pcmFormatFloat32, isInterleaved: false)
        ]
        engine.audioBuffers = [
            MockAudioBuffer(samples: [0.5, -0.5, 0.5, -0.5], sampleRate: 44_100)
        ]
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()
        await tunerDrainMainQueue()
        await Task.yield()
        await tunerDrainMainQueue()

        XCTAssertGreaterThan(service.inputSignalLevel, 0)
        XCTAssertNil(service.currentResult)
        XCTAssertEqual(service.inputDebugSnapshot.deviceSwitchStatus, noErr)
        XCTAssertEqual(service.inputDebugSnapshot.engineSampleRate, 44_100)
        XCTAssertEqual(service.inputDebugSnapshot.engineChannelCount, 1)
        XCTAssertEqual(service.inputDebugSnapshot.engineCommonFormat, .pcmFormatFloat32)
        XCTAssertEqual(service.inputDebugSnapshot.engineIsInterleaved, false)
        XCTAssertEqual(service.inputDebugSnapshot.tapCallbackCount, 0)
        XCTAssertEqual(service.inputDebugSnapshot.conversionStatus, .notStarted)
    }

    @MainActor
    func testTunerInputServiceIgnoresStaleSignalAfterStop() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()
        service.stop()
        engine.sendAudioBuffer(samples: [0.5, -0.5, 0.5, -0.5])
        await tunerDrainMainQueue()

        XCTAssertEqual(service.inputSignalLevel, 0)
    }

    @MainActor
    func testTunerInputServiceIgnoresEmptyInputBuffer() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()
        engine.sendAudioBuffer(samples: [])
        await tunerDrainMainQueue()

        XCTAssertEqual(service.inputSignalLevel, 0)
        XCTAssertNil(service.currentResult)
        XCTAssertEqual(service.inputDebugSnapshot.conversionStatus, .notStarted)
    }

    @MainActor
    func testTunerInputServiceIgnoresUnsupportedInputBuffer() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()
        engine.sendAudioBuffer(try makeTunerInt16Buffer(samples: [1000, -1000, 1000, -1000]))
        await tunerDrainMainQueue()

        XCTAssertEqual(service.inputSignalLevel, 0)
        XCTAssertNil(service.currentResult)
        XCTAssertEqual(service.inputDebugSnapshot.conversionStatus, .notStarted)
    }

    @MainActor
    func testTunerInputServiceIgnoresStaleSignalAfterInputDeviceRestart() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        provider.deviceIDs["input-2"] = 84
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()
        settingsStore.updateAudioInputDeviceUID("input-2")
        await tunerDrainMainQueue()
        await Task.yield()
        await tunerDrainMainQueue()

        XCTAssertEqual(engine.startDeviceIDs, [42, 84])

        engine.sendAudioBuffer(samples: [0.5, -0.5, 0.5, -0.5], toStartAt: 0)
        await tunerDrainMainQueue()

        XCTAssertEqual(service.inputSignalLevel, 0)
        XCTAssertEqual(service.inputDebugSnapshot.tapCallbackCount, 0)
    }

    @MainActor
    func testTunerInputServiceKeepsRunningWhenSignalLevelUpdates() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        engine.audioBuffers = [
            MockAudioBuffer(samples: tunerSineWave(frequency: 440, duration: 0.4), sampleRate: 44_100)
        ]
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()
        await tunerDrainMainQueue()

        XCTAssertGreaterThan(service.inputSignalLevel, 0)
        XCTAssertNil(service.errorMessage)
    }

    @MainActor
    func testTunerInputServiceCoalescesPendingAnalysisToLatestBuffer() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let detector = BlockingPitchDetector()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine,
            detector: detector
        )

        await service.start()
        engine.sendAudioBuffer(samples: tunerMarkerSamples(1))
        await fulfillment(of: [detector.firstDetectionStarted], timeout: 2)

        engine.sendAudioBuffer(samples: tunerMarkerSamples(2))
        engine.sendAudioBuffer(samples: tunerMarkerSamples(3))
        detector.releaseFirstDetection()

        let didPublishLatestResult = await waitForTunerMainActorCondition { service.currentResult?.noteName == "C" }
        XCTAssertTrue(didPublishLatestResult)
        XCTAssertEqual(detector.detectedMarkers, [1, 3])
    }

    @MainActor
    func testTunerInputServiceIgnoresStalePitchAfterStop() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let detector = BlockingPitchDetector()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine,
            detector: detector
        )

        await service.start()
        engine.sendAudioBuffer(samples: tunerMarkerSamples(1))
        await fulfillment(of: [detector.firstDetectionStarted], timeout: 2)

        service.stop()
        detector.releaseFirstDetection()
        await tunerDrainMainQueue()
        await Task.yield()
        await tunerDrainMainQueue()

        XCTAssertNil(service.currentResult)
    }

    @MainActor
    func testTunerInputServicePassesEngineSampleRateToDetector() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let detector = RecordingPitchDetector()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine,
            detector: detector
        )

        await service.start()
        engine.sendAudioBuffer(samples: tunerMarkerSamples(1), sampleRate: 48_000)

        let didRecordSampleRate = await waitForTunerMainActorCondition { detector.sampleRates == [48_000] }
        XCTAssertTrue(didRecordSampleRate)
    }
}
