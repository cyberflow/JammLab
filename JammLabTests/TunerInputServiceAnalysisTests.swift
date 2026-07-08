import CoreAudio
import XCTest
@testable import JammLab

final class TunerInputServiceAnalysisTests: XCTestCase {
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
