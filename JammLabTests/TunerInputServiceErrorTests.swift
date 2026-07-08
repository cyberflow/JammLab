import XCTest
@testable import JammLab

final class TunerInputServiceErrorTests: XCTestCase {
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
}
