import AVFoundation
import CoreAudio
import XCTest
@testable import JammLab

final class TunerInputServiceTests: XCTestCase {
    @MainActor
    func testTunerInputServiceRequestsPermissionOnlyWhenStarted() async throws {
        let defaults = try temporaryUserDefaults()
        let settingsStore = JammLab.AppSettingsStore(defaults: defaults)
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: false)
        ]
        provider.deviceIDs["input-1"] = 42
        let permission = MockAudioInputPermissionProvider(status: .notDetermined, requestResult: true)
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: permission,
            inputEngine: engine
        )

        XCTAssertEqual(permission.requestAccessCount, 0)
        XCTAssertEqual(engine.startDeviceIDs, [])

        await service.start()

        XCTAssertEqual(permission.requestAccessCount, 1)
        XCTAssertEqual(engine.startDeviceIDs, [42])
        XCTAssertNil(service.errorMessage)
    }

    @MainActor
    func testTunerInputServiceDoesNotStartEngineWhenPermissionDenied() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        let permission = MockAudioInputPermissionProvider(status: .denied)
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            inputPermissionProvider: permission,
            inputEngine: engine
        )

        await service.start()

        XCTAssertEqual(permission.requestAccessCount, 0)
        XCTAssertEqual(engine.startDeviceIDs, [])
        XCTAssertEqual(service.errorMessage, TunerInputServiceError.microphonePermissionDenied.localizedDescription)
        XCTAssertEqual(service.inputSignalLevel, 0)
        XCTAssertEqual(service.inputDebugSnapshot.permissionStatus, .denied)
        XCTAssertEqual(service.inputDebugSnapshot.permissionRequestGranted, false)
        XCTAssertEqual(service.inputDebugSnapshot.lastErrorMessage, TunerInputServiceError.microphonePermissionDenied.localizedDescription)
    }

    @MainActor
    func testTunerInputServiceFallsBackToDefaultWhenSavedInputIsUnavailableWithoutClearingSetting() async throws {
        let defaults = try temporaryUserDefaults()
        let settingsStore = JammLab.AppSettingsStore(defaults: defaults)
        settingsStore.updateAudioInputDeviceUID("missing-input")
        let provider = MockAudioDeviceProvider()
        provider.defaultInputDeviceID = 7
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "default-input", name: "Default Input", kind: .input, isDefault: true)
        ]
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()

        XCTAssertEqual(engine.startDeviceIDs, [7])
        XCTAssertEqual(settingsStore.audioDeviceSettings.inputDeviceUID, "missing-input")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).audioDeviceSettings.inputDeviceUID, "missing-input")
        XCTAssertEqual(service.inputDeviceName, "Default Input")
        XCTAssertEqual(service.inputDiagnosticMessage, "Selected tuner input is unavailable. Using System Default.")
        XCTAssertEqual(service.inputDebugSnapshot.savedInputDeviceUID, "missing-input")
        XCTAssertEqual(service.inputDebugSnapshot.resolvedDeviceName, "Default Input")
        XCTAssertEqual(service.inputDebugSnapshot.resolvedDeviceID, 7)
        XCTAssertTrue(service.inputDebugSnapshot.didFallbackToDefaultDevice)
        XCTAssertNil(service.errorMessage)
    }

    @MainActor
    func testTunerInputServiceIgnoresOutputDeviceChangesWhileRunning() async throws {
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
        XCTAssertEqual(engine.startDeviceIDs, [42])

        settingsStore.updateAudioOutputDeviceUID("output-1")
        await drainMainQueue()

        XCTAssertEqual(engine.startDeviceIDs, [42])
    }

    @MainActor
    func testTunerInputServiceRestartsForInputDeviceChangesWhileRunning() async throws {
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
        await drainMainQueue()
        await Task.yield()
        await drainMainQueue()

        XCTAssertEqual(engine.startDeviceIDs, [42, 84])
        XCTAssertGreaterThanOrEqual(engine.stopCallCount, 2)
    }

    @MainActor
    func testTunerInputServicePublishesInputDeviceSwitchErrors() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        engine.startErrors = [TunerInputServiceError.inputDeviceSwitchFailed(-1)]
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()

        XCTAssertEqual(engine.startDeviceIDs, [42])
        XCTAssertGreaterThanOrEqual(engine.stopCallCount, 1)
        XCTAssertEqual(service.errorMessage, TunerInputServiceError.inputDeviceSwitchFailed(-1).localizedDescription)
    }

    @MainActor
    func testTunerInputServicePublishesNamedInvalidElementStatus() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        settingsStore.updateAudioInputDeviceUID("input-1")
        let provider = MockAudioDeviceProvider()
        provider.deviceIDs["input-1"] = 42
        let engine = MockTunerInputEngine()
        engine.startErrors = [TunerInputServiceError.inputDeviceSwitchFailed(-10877)]
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()

        XCTAssertEqual(
            service.errorMessage,
            "Audio input device switch failed with status -10877 (kAudioUnitErr_InvalidElement)."
        )
        XCTAssertEqual(service.inputDebugSnapshot.deviceSwitchStatus, -10877)
        XCTAssertEqual(
            service.inputDebugSnapshot.lastErrorMessage,
            "Audio input device switch failed with status -10877 (kAudioUnitErr_InvalidElement)."
        )
        XCTAssertEqual(service.inputSignalLevel, 0)
    }

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
        await drainMainQueue()
        await Task.yield()
        await drainMainQueue()

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
        await drainMainQueue()

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
        await drainMainQueue()

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
        engine.sendAudioBuffer(try makeInt16Buffer(samples: [1000, -1000, 1000, -1000]))
        await drainMainQueue()

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
        await drainMainQueue()
        await Task.yield()
        await drainMainQueue()

        XCTAssertEqual(engine.startDeviceIDs, [42, 84])

        engine.sendAudioBuffer(samples: [0.5, -0.5, 0.5, -0.5], toStartAt: 0)
        await drainMainQueue()

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
            MockAudioBuffer(samples: sineWave(frequency: 440, duration: 0.4), sampleRate: 44_100)
        ]
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: MockAudioInputPermissionProvider(status: .authorized),
            inputEngine: engine
        )

        await service.start()
        await drainMainQueue()

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
        engine.sendAudioBuffer(samples: markerSamples(1))
        await fulfillment(of: [detector.firstDetectionStarted], timeout: 2)

        engine.sendAudioBuffer(samples: markerSamples(2))
        engine.sendAudioBuffer(samples: markerSamples(3))
        detector.releaseFirstDetection()

        let didPublishLatestResult = await waitForMainActorCondition { service.currentResult?.noteName == "C" }
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
        engine.sendAudioBuffer(samples: markerSamples(1))
        await fulfillment(of: [detector.firstDetectionStarted], timeout: 2)

        service.stop()
        detector.releaseFirstDetection()
        await drainMainQueue()
        await Task.yield()
        await drainMainQueue()

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
        engine.sendAudioBuffer(samples: markerSamples(1), sampleRate: 48_000)

        let didRecordSampleRate = await waitForMainActorCondition { detector.sampleRates == [48_000] }
        XCTAssertTrue(didRecordSampleRate)
    }

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
        engine.sendAudioBuffer(samples: markerSamples(1))
        let didPublishDetectedNote = await waitForMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishDetectedNote)

        engine.sendAudioBuffer(samples: markerSamples(2))
        let didProcessMissingResult = await waitForMainActorCondition { detector.detectCallCount == 2 }
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
        engine.sendAudioBuffer(samples: markerSamples(1))
        let didPublishDetectedNote = await waitForMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishDetectedNote)

        engine.sendAudioBuffer(samples: markerSamples(2))
        let didProcessMissingResult = await waitForMainActorCondition { detector.detectCallCount == 2 }
        XCTAssertTrue(didProcessMissingResult)
        let didClearHeldNote = await waitForMainActorCondition { service.currentResult == nil }
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
        engine.sendAudioBuffer(samples: markerSamples(1))
        let didPublishFirstNote = await waitForMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishFirstNote)

        engine.sendAudioBuffer(samples: markerSamples(2))
        let didPublishReplacementNote = await waitForMainActorCondition { service.currentResult?.noteName == "C" }
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
        engine.sendAudioBuffer(samples: markerSamples(1))
        let didPublishDetectedNote = await waitForMainActorCondition { service.currentResult?.noteName == "A" }
        XCTAssertTrue(didPublishDetectedNote)

        engine.sendAudioBuffer(samples: markerSamples(2))
        let didProcessMissingResult = await waitForMainActorCondition { detector.detectCallCount == 2 }
        XCTAssertTrue(didProcessMissingResult)
        service.stop()

        XCTAssertNil(service.currentResult)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(service.currentResult)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func sineWave(
        frequency: Double,
        duration: Double,
        sampleRate: Double = 44_100,
        amplitude: Float = 0.5
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        return (0..<count).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            return amplitude * Float(sin(phase))
        }
    }

    private func markerSamples(_ marker: Float) -> [Float] {
        Array(repeating: marker, count: 128)
    }

    @MainActor
    private func waitForMainActorCondition(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func makeInt16Buffer(samples: [Int16], sampleRate: Double = 44_100) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(max(samples.count, 1))
        ))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.int16ChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channel[index] = sample
            }
        }
        return buffer
    }

}

private extension PitchDetectionResult {
    static func result(
        noteName: String,
        octave: Int,
        frequencyHz: Double,
        midiNote: Int
    ) -> PitchDetectionResult {
        PitchDetectionResult(
            frequencyHz: frequencyHz,
            midiNote: midiNote,
            noteName: noteName,
            octave: octave,
            centsOffset: 0,
            confidence: 1,
            rms: 1
        )
    }
}
