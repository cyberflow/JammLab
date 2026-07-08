import CoreAudio
import XCTest
@testable import JammLab

final class TunerInputServiceNoteHoldTests: XCTestCase {
    @MainActor
    func testTunerInputServiceKeepsDetectedNoteDuringHoldWindow() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let detector = QueuedPitchDetector(results: [
            .result(noteName: "A", octave: 4, frequencyHz: 440, midiNote: 69),
            nil
        ])
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine,
            detector: detector,
            noteHoldDuration: 0.2
        )

        await service.start()
        engine.sendAudioBuffer(samples: tunerMarkerSamples(1))
        let didPublishDetectedNote = await waitForTunerMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishDetectedNote)

        engine.sendAudioBuffer(samples: tunerMarkerSamples(2))
        let didProcessMissingResult = await waitForTunerMainActorCondition { detector.detectCallCount == 2 }
        XCTAssertTrue(didProcessMissingResult)

        XCTAssertEqual(service.currentResult?.noteName, "A")
        XCTAssertEqual(service.currentResult?.octave, 4)
    }

    @MainActor
    func testTunerInputServiceClearsHeldNoteAfterHoldWindowWithoutAnotherBuffer() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let detector = QueuedPitchDetector(results: [
            .result(noteName: "A", octave: 4, frequencyHz: 440, midiNote: 69),
            nil
        ])
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine,
            detector: detector,
            noteHoldDuration: 0.03
        )

        await service.start()
        engine.sendAudioBuffer(samples: tunerMarkerSamples(1))
        let didPublishDetectedNote = await waitForTunerMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishDetectedNote)

        engine.sendAudioBuffer(samples: tunerMarkerSamples(2))
        let didProcessMissingResult = await waitForTunerMainActorCondition { detector.detectCallCount == 2 }
        XCTAssertTrue(didProcessMissingResult)
        let didClearHeldNote = await waitForTunerMainActorCondition { service.currentResult == nil }
        XCTAssertTrue(didClearHeldNote)
    }

    @MainActor
    func testTunerInputServiceReplacesHeldNoteWithNewDetectionImmediately() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let detector = QueuedPitchDetector(results: [
            .result(noteName: "A", octave: 4, frequencyHz: 440, midiNote: 69),
            .result(noteName: "C", octave: 5, frequencyHz: 523.25, midiNote: 72)
        ])
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine,
            detector: detector,
            noteHoldDuration: 1.0
        )

        await service.start()
        engine.sendAudioBuffer(samples: tunerMarkerSamples(1))
        let didPublishFirstNote = await waitForTunerMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishFirstNote)

        engine.sendAudioBuffer(samples: tunerMarkerSamples(2))
        let didPublishReplacementNote = await waitForTunerMainActorCondition { service.currentResult?.noteName == "C" }
        XCTAssertTrue(didPublishReplacementNote)
        XCTAssertEqual(service.currentResult?.octave, 5)
    }

    @MainActor
    func testTunerInputServiceClearsHeldNoteOnStopAndCancelsHoldClear() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        let detector = QueuedPitchDetector(results: [
            .result(noteName: "A", octave: 4, frequencyHz: 440, midiNote: 69),
            nil
        ])
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine,
            detector: detector,
            noteHoldDuration: 0.2
        )

        await service.start()
        engine.sendAudioBuffer(samples: tunerMarkerSamples(1))
        let didPublishDetectedNote = await waitForTunerMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishDetectedNote)

        engine.sendAudioBuffer(samples: tunerMarkerSamples(2))
        let didProcessMissingResult = await waitForTunerMainActorCondition { detector.detectCallCount == 2 }
        XCTAssertTrue(didProcessMissingResult)
        service.stop()

        XCTAssertNil(service.currentResult)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(service.currentResult)
    }
}
