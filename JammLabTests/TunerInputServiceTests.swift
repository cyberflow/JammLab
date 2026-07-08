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
        await tunerDrainMainQueue()

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
        await tunerDrainMainQueue()
        await Task.yield()
        await tunerDrainMainQueue()

        XCTAssertEqual(engine.startDeviceIDs, [42, 84])
        XCTAssertGreaterThanOrEqual(engine.stopCallCount, 2)
    }

}
