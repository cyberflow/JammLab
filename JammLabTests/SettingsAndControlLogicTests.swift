import AVFoundation
import CoreAudio
import XCTest
@testable import JammLab

final class SettingsAndControlLogicTests: XCTestCase {
    @MainActor
    func testRecentProjectsStoreLoadsValidProjectEntries() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "valid.jammlab", contents: "{}")
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let entry = RecentProjectEntry(
            displayName: "Valid",
            bookmarkData: try ProjectDocumentService().bookmarkData(for: projectURL)
        )

        defaults.set(try JSONEncoder().encode([entry]), forKey: RecentProjectsStore.defaultsKey)
        let store = RecentProjectsStore(defaults: defaults)

        XCTAssertEqual(store.entries.map(\.displayName), ["Valid"])
    }

    @MainActor
    func testRecentProjectsStorePrunesMissingProjectEntriesOnLoad() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "missing.jammlab", contents: "{}")
        let projectDirectory = projectURL.deletingLastPathComponent()
        let entry = RecentProjectEntry(
            displayName: "Missing",
            bookmarkData: try ProjectDocumentService().bookmarkData(for: projectURL)
        )
        try FileManager.default.removeItem(at: projectDirectory)

        defaults.set(try JSONEncoder().encode([entry]), forKey: RecentProjectsStore.defaultsKey)
        let store = RecentProjectsStore(defaults: defaults)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(RecentProjectsStore(defaults: defaults).entries.isEmpty)
    }

    @MainActor
    func testRecentProjectsStorePrunesUnsupportedExtensionsOnLoad() throws {
        let defaults = try temporaryUserDefaults()
        let textURL = try temporaryFile(name: "notes.txt", contents: "not a project")
        defer { try? FileManager.default.removeItem(at: textURL.deletingLastPathComponent()) }
        let entry = RecentProjectEntry(
            displayName: "Notes",
            bookmarkData: try ProjectDocumentService().bookmarkData(for: textURL)
        )

        defaults.set(try JSONEncoder().encode([entry]), forKey: RecentProjectsStore.defaultsKey)
        let store = RecentProjectsStore(defaults: defaults)

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testRecentProjectsStoreDeduplicatesProjectsWhenAdding() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "dedupe.jammlab", contents: "{}")
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let projectService = ProjectDocumentService()
        let store = RecentProjectsStore(defaults: defaults)

        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))
        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.displayName, "dedupe")
    }

    @MainActor
    func testRecentProjectsStoreClearPersistsEmptyList() throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "clear.jammlab", contents: "{}")
        defer { try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent()) }
        let projectService = ProjectDocumentService()
        let store = RecentProjectsStore(defaults: defaults)

        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))
        XCTAssertFalse(store.entries.isEmpty)

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(RecentProjectsStore(defaults: defaults).entries.isEmpty)
    }

    func testAppSettingsStoreDefaultsAndPersistsStemBackendComputeMode() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.stemBackendComputeMode, .cpuOnly)

        store.updateStemBackendComputeMode(.auto)

        XCTAssertEqual(AppSettingsStore(defaults: defaults).stemBackendComputeMode, .auto)
    }

    func testAppSettingsStoreFallsBackForInvalidStemBackendComputeMode() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set("mps", forKey: AppSettingsStore.stemBackendComputeModeKey)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.stemBackendComputeMode, .cpuOnly)
    }

    func testAudioDeviceSettingsDefaultIsSystemDefault() {
        XCTAssertNil(AudioDeviceSettings.defaultValue.inputDeviceUID)
        XCTAssertNil(AudioDeviceSettings.defaultValue.outputDeviceUID)
    }

    func testAppSettingsStorePersistsRestoresAndResetsAudioDeviceSettings() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.audioDeviceSettings, .defaultValue)

        store.updateAudioInputDeviceUID("input-device")
        store.updateAudioOutputDeviceUID("output-device")

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.audioDeviceSettings.inputDeviceUID, "input-device")
        XCTAssertEqual(restored.audioDeviceSettings.outputDeviceUID, "output-device")

        restored.resetAudioDevicesToSystemDefault()

        XCTAssertEqual(restored.audioDeviceSettings, .defaultValue)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).audioDeviceSettings, .defaultValue)
    }

    func testAppSettingsStoreResetAudioOutputPreservesInputDevice() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.updateAudioInputDeviceUID("input-device")
        store.updateAudioOutputDeviceUID("output-device")

        store.resetAudioOutputDeviceToSystemDefault()

        XCTAssertEqual(store.audioDeviceSettings.inputDeviceUID, "input-device")
        XCTAssertNil(store.audioDeviceSettings.outputDeviceUID)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).audioDeviceSettings.inputDeviceUID, "input-device")
        XCTAssertNil(AppSettingsStore(defaults: defaults).audioDeviceSettings.outputDeviceUID)
    }

    func testAppSettingsStoreResetAudioInputPreservesOutputDevice() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.updateAudioInputDeviceUID("input-device")
        store.updateAudioOutputDeviceUID("output-device")

        store.resetAudioInputDeviceToSystemDefault()

        XCTAssertNil(store.audioDeviceSettings.inputDeviceUID)
        XCTAssertEqual(store.audioDeviceSettings.outputDeviceUID, "output-device")
        XCTAssertNil(AppSettingsStore(defaults: defaults).audioDeviceSettings.inputDeviceUID)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).audioDeviceSettings.outputDeviceUID, "output-device")
    }

    func testAppSettingsStoreNormalizesEmptyAudioDeviceUIDs() throws {
        let defaults = try temporaryUserDefaults()
        let settings = AudioDeviceSettings(inputDeviceUID: "   ", outputDeviceUID: "\n")
        defaults.set(try JSONEncoder().encode(settings), forKey: AppSettingsStore.audioDeviceSettingsKey)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.audioDeviceSettings, .defaultValue)
    }

    func testAudioSettingsDeviceLoaderDoesNotReadInputDevicesBeforePermission() async {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]
        provider.outputDevicesResult = [
            AudioDeviceInfo(uid: "output-1", name: "Output 1", kind: .output, isDefault: true)
        ]
        let permission = MockAudioInputPermissionProvider(status: .notDetermined)
        let loader = AudioSettingsDeviceLoader(deviceProvider: provider, inputPermissionProvider: permission)

        let result = await loader.refreshDevices()

        XCTAssertEqual(provider.inputDevicesCallCount, 0)
        XCTAssertEqual(provider.outputDevicesCallCount, 1)
        XCTAssertEqual(result.inputDevices, [])
        XCTAssertEqual(result.outputDevices.map(\.uid), ["output-1"])
        XCTAssertEqual(result.inputPermissionStatus, .notDetermined)
        XCTAssertEqual(permission.requestAccessCount, 0)
    }

    func testAudioSettingsDeviceLoaderReadsInputDevicesAfterPermission() async {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]
        provider.outputDevicesResult = [
            AudioDeviceInfo(uid: "output-1", name: "Output 1", kind: .output, isDefault: true)
        ]
        let permission = MockAudioInputPermissionProvider(status: .authorized)
        let loader = AudioSettingsDeviceLoader(deviceProvider: provider, inputPermissionProvider: permission)

        let result = await loader.refreshDevices()

        XCTAssertEqual(provider.inputDevicesCallCount, 1)
        XCTAssertEqual(provider.outputDevicesCallCount, 1)
        XCTAssertEqual(result.inputDevices.map(\.uid), ["input-1"])
        XCTAssertEqual(result.outputDevices.map(\.uid), ["output-1"])
        XCTAssertEqual(permission.requestAccessCount, 0)
    }

    func testAudioSettingsDevicePickerShowsSystemDefaultForUnavailableSavedUID() {
        let devices = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]

        XCTAssertNil(AudioSettingsDevicePickerSelection.visibleUID(
            selectedUID: "missing-input",
            devices: devices
        ))
    }

    func testAudioSettingsDevicePickerUsesSavedUIDWhenAvailable() {
        let devices = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]

        XCTAssertEqual(
            AudioSettingsDevicePickerSelection.visibleUID(selectedUID: "input-1", devices: devices),
            "input-1"
        )
    }

    func testTunerInputDeviceResolverUsesSavedInputDevice() throws {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Interface Input", kind: .input, isDefault: false)
        ]
        provider.deviceIDs["input-1"] = 42
        provider.defaultInputDeviceID = 7

        let selection = try TunerInputDeviceResolver(audioDeviceProvider: provider)
            .resolveInputDevice(selectedUID: "input-1")

        XCTAssertEqual(selection.id, 42)
        XCTAssertEqual(selection.name, "Interface Input")
        XCTAssertEqual(provider.defaultDeviceCallKinds, [])
    }

    func testTunerInputDeviceResolverUsesDefaultWhenInputSelectionIsNil() throws {
        let provider = MockAudioDeviceProvider()
        provider.defaultInputDeviceID = 7
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "default-input", name: "Default Input", kind: .input, isDefault: true)
        ]

        let selection = try TunerInputDeviceResolver(audioDeviceProvider: provider)
            .resolveInputDevice(selectedUID: nil)

        XCTAssertEqual(selection.id, 7)
        XCTAssertEqual(selection.name, "Default Input")
    }

    func testTunerInputDeviceResolverDoesNotFallbackWhenSavedInputDeviceIsMissing() {
        let provider = MockAudioDeviceProvider()
        provider.defaultInputDeviceID = 7

        XCTAssertThrowsError(
            try TunerInputDeviceResolver(audioDeviceProvider: provider)
                .resolveInputDevice(selectedUID: "missing-input")
        )
        XCTAssertEqual(provider.defaultDeviceCallKinds, [])
    }

    func testTunerInputServiceErrorNamesInvalidElementStatusForUsers() {
        XCTAssertEqual(
            TunerInputServiceError.inputDeviceSwitchFailed(-10877).localizedDescription,
            "Audio input device switch failed with status -10877 (kAudioUnitErr_InvalidElement)."
        )
    }

    func testTunerInputSignalLevelNormalizesRMSAsDBFS() {
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: 0), 0)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -70.0 / 20.0)), 0)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -60.0 / 20.0)), 0)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -36.0 / 20.0)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -12.0 / 20.0)), 1)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: 1), 1)
    }

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

    func testDefaultColorPaletteMatchesAppDefaults() {
        let palette = AppColorPalette.defaultValue

        for role in AppColorRole.allCases {
            XCTAssertEqual(palette.hex(for: role), role.defaultHex)
        }
        XCTAssertEqual(palette.hex(for: .controlActive), "#878787")
        XCTAssertEqual(palette.hex(for: .loopButtonActive), "#3CAF96")
        XCTAssertEqual(palette.hex(for: .statusButtonFill), "#202020")
        XCTAssertEqual(palette.hex(for: .statusButtonCriticalFill), "#D00000")
        XCTAssertEqual(palette.hex(for: .statusButtonAttentionFill), "#C8D300")
        XCTAssertEqual(palette.hex(for: .valueSliderFill), "#00AFC8")
        XCTAssertEqual(palette.hex(for: .waveformBackground), "#A9A9A9")
        XCTAssertEqual(palette.hex(for: .waveformColor), "#212121")
        XCTAssertEqual(palette.hex(for: .waveformDisabledBackground), "#5C5C5C")
        XCTAssertEqual(palette.hex(for: .waveformDisabledColor), "#2F2F2F")
        XCTAssertEqual(palette.hex(for: .timeTrackAccentBeatLine), "#747474")
        XCTAssertEqual(palette.hex(for: .timeTrackBeatLine), "#AEAEAE")
        XCTAssertEqual(palette.hex(for: .waveformAccentBeatLine), "#0C0C0C")
        XCTAssertEqual(palette.hex(for: .waveformBeatLine), "#0C0C0C")
    }

    func testThemeColorGroupsCoverEveryRoleOnce() {
        let groupedRoles = AppColorRoleGroup.allCases.flatMap(\.roles)

        XCTAssertEqual(groupedRoles.count, AppColorRole.allCases.count)
        XCTAssertEqual(Set(groupedRoles), Set(AppColorRole.allCases))
    }

    func testAppSettingsStorePersistsRestoresAndResetsColorPalette() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.updateColor(.accent, hex: "#123456")
        store.updateColor(.appBackground, hex: "abcdef")

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.colorPalette.hex(for: .accent), "#123456")
        XCTAssertEqual(restored.colorPalette.hex(for: .appBackground), "#ABCDEF")

        store.resetColorPaletteToDefaults()

        XCTAssertEqual(store.colorPalette, .defaultValue)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).colorPalette, .defaultValue)
    }

    func testColorPaletteFallsBackForInvalidHexValues() throws {
        let defaults = try temporaryUserDefaults()
        let invalidPalette = AppColorPalette(values: [
            AppColorRole.accent.rawValue: "not-a-color",
            AppColorRole.primaryText.rawValue: "#FFFF"
        ])
        defaults.set(try JSONEncoder().encode(invalidPalette), forKey: AppSettingsStore.colorPaletteKey)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.colorPalette.hex(for: .accent), AppColorRole.accent.defaultHex)
        XCTAssertEqual(store.colorPalette.hex(for: .primaryText), AppColorRole.primaryText.defaultHex)
    }

    func testColorPaletteMergesPartialSavedValuesWithDefaults() throws {
        let defaults = try temporaryUserDefaults()
        let partialPalette = AppColorPalette(values: [
            AppColorRole.accent.rawValue: "#010203"
        ])
        defaults.set(try JSONEncoder().encode(partialPalette), forKey: AppSettingsStore.colorPaletteKey)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.colorPalette.hex(for: .accent), "#010203")
        XCTAssertEqual(store.colorPalette.hex(for: .panelBackground), AppColorRole.panelBackground.defaultHex)
        XCTAssertEqual(store.colorPalette.hex(for: .timeTrackAccentBeatLine), AppColorRole.timeTrackAccentBeatLine.defaultHex)
        XCTAssertEqual(store.colorPalette.hex(for: .waveformBeatLine), AppColorRole.waveformBeatLine.defaultHex)
    }

    func testColorPaletteDropsRemovedSavedKeysAfterNormalization() throws {
        let defaults = try temporaryUserDefaults()
        let savedPalette = AppColorPalette(values: [
            AppColorRole.accent.rawValue: "#010203",
            "accentText": "#112233"
        ])
        defaults.set(try JSONEncoder().encode(savedPalette), forKey: AppSettingsStore.colorPaletteKey)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.colorPalette.hex(for: .accent), "#010203")

        let restoredData = try JSONEncoder().encode(store.colorPalette)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: restoredData) as? [String: Any])
        let values = try XCTUnwrap(object["values"] as? [String: String])

        XCTAssertNil(values["accentText"])
        XCTAssertEqual(values.count, AppColorRole.allCases.count)
    }

    func testAbletonNumberFieldLogicClampsAndResetsDefault() {
        let config = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 300,
            step: 1,
            precision: 0
        )

        XCTAssertEqual(AbletonNumberFieldLogic.clamp(20, configuration: config), 40, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.clamp(300, configuration: config), 240, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.resetValue(configuration: config), 240, accuracy: 0.0001)
    }

    func testAbletonNumberFieldLogicSnapsToIntegerAndFractionalSteps() {
        let integerConfig = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 120,
            step: 1,
            precision: 0
        )
        let fractionalConfig = AbletonNumberFieldConfiguration(
            minValue: -1,
            maxValue: 1,
            defaultValue: 0,
            step: 0.25,
            precision: 2
        )

        XCTAssertEqual(AbletonNumberFieldLogic.snapToStep(120.4, configuration: integerConfig), 120, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.snapToStep(120.6, configuration: integerConfig), 121, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.snapToStep(0.38, configuration: fractionalConfig), 0.5, accuracy: 0.0001)
    }

    func testAbletonNumberFieldLogicFormatsPrecision() {
        let integerConfig = AbletonNumberFieldConfiguration(
            minValue: 0,
            maxValue: 200,
            defaultValue: 120,
            step: 1,
            precision: 0
        )
        let decimalConfig = AbletonNumberFieldConfiguration(
            minValue: 0,
            maxValue: 2,
            defaultValue: 1,
            step: 0.01,
            precision: 2
        )
        let tempoConfig = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 120,
            step: 0.01,
            precision: 2
        )

        XCTAssertEqual(AbletonNumberFieldLogic.format(119.6, configuration: integerConfig), "120")
        XCTAssertEqual(AbletonNumberFieldLogic.format(1.235, configuration: decimalConfig), "1.24")
        XCTAssertEqual(AbletonNumberFieldLogic.format(120, configuration: tempoConfig), "120.00")
        XCTAssertEqual(AbletonNumberFieldLogic.format(240, configuration: tempoConfig), "240.00")
    }

    func testAbletonNumberFieldLogicParsesDecimalSeparatorsAndNegativeRules() {
        let positiveConfig = AbletonNumberFieldConfiguration(
            minValue: 0,
            maxValue: 200,
            defaultValue: 120,
            step: 0.1,
            precision: 1
        )
        let negativeConfig = AbletonNumberFieldConfiguration(
            minValue: -12,
            maxValue: 12,
            defaultValue: 0,
            step: 0.5,
            precision: 1
        )
        let hundredthsConfig = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 120,
            step: 0.01,
            precision: 2
        )

        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("123,4", configuration: positiveConfig)), 123.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("123.45", configuration: positiveConfig)), 123.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("123.45", configuration: hundredthsConfig)), 123.45, accuracy: 0.0001)
        XCTAssertNil(AbletonNumberFieldLogic.parse("-1", configuration: positiveConfig))
        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("-1.2", configuration: negativeConfig)), -1, accuracy: 0.0001)
        XCTAssertNil(AbletonNumberFieldLogic.parse("abc", configuration: negativeConfig))
    }

    func testJammValueSliderLogicClampsAndResetsDefault() {
        let config = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 1,
            defaultValue: 1.5,
            step: 0.01,
            precision: 2
        )

        XCTAssertEqual(JammValueSliderLogic.clamp(-1, configuration: config), 0, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.clamp(2, configuration: config), 1, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.resetValue(configuration: config), 1, accuracy: 0.0001)
    }

    func testJammValueSliderLogicNormalizesRanges() {
        let volumeConfig = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.75,
            step: 0.01,
            precision: 2
        )
        let gainConfig = JammValueSliderConfiguration(
            minValue: -60,
            maxValue: 12,
            defaultValue: 0,
            step: 0.1,
            precision: 1
        )
        let reversedConfig = JammValueSliderConfiguration(
            minValue: 12,
            maxValue: -60,
            defaultValue: 0,
            step: 0.1,
            precision: 1
        )

        XCTAssertEqual(JammValueSliderLogic.normalizedValue(0.25, configuration: volumeConfig), 0.25, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(-60, configuration: gainConfig), 0, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(12, configuration: gainConfig), 1, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(-24, configuration: gainConfig), 0.5, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(-24, configuration: reversedConfig), 0.5, accuracy: 0.0001)
    }

    func testJammValueSliderLogicSnapsAndFormats() {
        let integerConfig = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 10,
            defaultValue: 5,
            step: 1,
            precision: 0
        )
        let fractionalConfig = JammValueSliderConfiguration(
            minValue: -1,
            maxValue: 1,
            defaultValue: 0,
            step: 0.25,
            precision: 2
        )

        XCTAssertEqual(JammValueSliderLogic.snapToStep(4.4, configuration: integerConfig), 4, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.snapToStep(4.6, configuration: integerConfig), 5, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.snapToStep(0.38, configuration: fractionalConfig), 0.5, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.format(0.38, configuration: fractionalConfig), "0.50")
    }

    func testJammValueSliderLogicUsesDominantDragAxis() {
        let config = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            step: 0.01,
            sensitivity: 1,
            precision: 2
        )

        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: 10, deltaY: 2, configuration: config), 0.6, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: 2, deltaY: 10, configuration: config), 0.6, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: -10, deltaY: 2, configuration: config), 0.4, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: 2, deltaY: -10, configuration: config), 0.4, accuracy: 0.0001)
    }

    func testJammValueSliderLogicSupportsSlowerIntegerPitchDrag() {
        let config = JammValueSliderConfiguration(
            minValue: -12,
            maxValue: 12,
            defaultValue: 0,
            step: 1,
            sensitivity: 0.08,
            precision: 0
        )

        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0, deltaX: 6, deltaY: 0, configuration: config), 0, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0, deltaX: 7, deltaY: 0, configuration: config), 1, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0, deltaX: -7, deltaY: 0, configuration: config), -1, accuracy: 0.0001)
    }

    func testAppKitDragThresholdUsesVerticalDistanceForNumberField() {
        XCTAssertFalse(AppKitDragThreshold.exceedsVerticalThreshold(deltaY: 2.9, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsVerticalThreshold(deltaY: 3, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsVerticalThreshold(deltaY: -3.1, threshold: 3))
    }

    func testAppKitDragThresholdUsesDominantAxisForValueSlider() {
        XCTAssertFalse(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: 2.9, deltaY: 1, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: 3, deltaY: 1, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: 1, deltaY: -3.1, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: -2, deltaY: 4, threshold: 3))
    }

    func testClickSoundSettingsDefaultsMatchCurrentGeneratedClick() {
        let defaults = ClickSoundSettings.defaultValue

        XCTAssertEqual(defaults.accentFrequencyHz, 1_760, accuracy: 0.0001)
        XCTAssertEqual(defaults.regularFrequencyHz, 1_120, accuracy: 0.0001)
        XCTAssertEqual(defaults.accentLengthMs, 36, accuracy: 0.0001)
        XCTAssertEqual(defaults.regularLengthMs, 26, accuracy: 0.0001)
    }

    func testAppSettingsStorePersistsRestoresAndResetsClickSoundSettings() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)
        let custom = ClickSoundSettings(
            accentFrequencyHz: 2_000,
            regularFrequencyHz: 900,
            accentLengthMs: 40,
            regularLengthMs: 20
        )

        store.updateClickSoundSettings(custom)

        XCTAssertEqual(AppSettingsStore(defaults: defaults).clickSoundSettings, custom)

        store.resetClickSoundSettingsToDefaults()

        XCTAssertEqual(store.clickSoundSettings, .defaultValue)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).clickSoundSettings, .defaultValue)
    }

    func testAppSettingsStoreClampsInvalidClickSoundSettings() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.updateClickSoundSettings(ClickSoundSettings(
            accentFrequencyHz: 20,
            regularFrequencyHz: 10_000,
            accentLengthMs: -4,
            regularLengthMs: 400
        ))

        XCTAssertEqual(store.clickSoundSettings.accentFrequencyHz, 100, accuracy: 0.0001)
        XCTAssertEqual(store.clickSoundSettings.regularFrequencyHz, 8_000, accuracy: 0.0001)
        XCTAssertEqual(store.clickSoundSettings.accentLengthMs, 1, accuracy: 0.0001)
        XCTAssertEqual(store.clickSoundSettings.regularLengthMs, 200, accuracy: 0.0001)
    }

}

private final class MockAudioDeviceProvider: AudioDeviceProviding {
    var inputDevicesResult: [AudioDeviceInfo] = []
    var outputDevicesResult: [AudioDeviceInfo] = []
    var deviceIDs: [String: AudioDeviceID] = [:]
    var defaultInputDeviceID = AudioDeviceID(1)
    var defaultOutputDeviceID = AudioDeviceID(2)
    var inputDevicesCallCount = 0
    var outputDevicesCallCount = 0
    var defaultDeviceCallKinds: [AudioDeviceKind] = []

    func inputDevices() throws -> [AudioDeviceInfo] {
        inputDevicesCallCount += 1
        return inputDevicesResult
    }

    func outputDevices() throws -> [AudioDeviceInfo] {
        outputDevicesCallCount += 1
        return outputDevicesResult
    }

    func deviceID(forUID uid: String, kind: AudioDeviceKind) throws -> AudioDeviceID {
        guard let deviceID = deviceIDs[uid] else {
            throw AudioDeviceServiceError.deviceNotFound(uid)
        }
        return deviceID
    }

    func defaultDeviceID(kind: AudioDeviceKind) throws -> AudioDeviceID {
        defaultDeviceCallKinds.append(kind)
        switch kind {
        case .input:
            return defaultInputDeviceID
        case .output:
            return defaultOutputDeviceID
        }
    }
}

private final class MockAudioInputPermissionProvider: AudioInputPermissionProviding {
    var authorizationStatus: AudioInputPermissionStatus
    var requestAccessCount = 0
    var requestResult: Bool

    init(status: AudioInputPermissionStatus, requestResult: Bool = false) {
        self.authorizationStatus = status
        self.requestResult = requestResult
    }

    func requestAccess() async -> Bool {
        requestAccessCount += 1
        authorizationStatus = requestResult ? .authorized : .denied
        return requestResult
    }
}

private struct MockAudioBuffer {
    let samples: [Float]
    let sampleRate: Double
}

private final class MockTunerInputEngine: TunerInputEngineControlling {
    var startDeviceIDs: [AudioDeviceID] = []
    var stopCallCount = 0
    var startErrors: [Error] = []
    var debugEvents: [TunerInputEngineDebugEvent] = []
    var audioBuffers: [MockAudioBuffer] = []
    private var audioBufferHandlers: [((AVAudioPCMBuffer, Double) -> Void)] = []
    private var debugHandlers: [((TunerInputEngineDebugEvent) -> Void)] = []

    func start(
        deviceID: AudioDeviceID,
        bufferSize: AVAudioFrameCount,
        onDebug: @escaping (TunerInputEngineDebugEvent) -> Void,
        onAudioBuffer: @escaping (AVAudioPCMBuffer, Double) -> Void
    ) throws {
        startDeviceIDs.append(deviceID)
        if !startErrors.isEmpty {
            throw startErrors.removeFirst()
        }
        debugHandlers.append(onDebug)
        audioBufferHandlers.append(onAudioBuffer)
        for event in debugEvents {
            onDebug(event)
        }
        for audioBuffer in audioBuffers {
            sendAudioBuffer(samples: audioBuffer.samples, sampleRate: audioBuffer.sampleRate)
        }
    }

    func stop() {
        stopCallCount += 1
    }

    func sendAudioBuffer(samples: [Float], sampleRate: Double = 44_100, toStartAt startIndex: Int? = nil) {
        sendAudioBuffer(Self.makeBuffer(samples: samples, sampleRate: sampleRate), sampleRate: sampleRate, toStartAt: startIndex)
    }

    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double = 44_100, toStartAt startIndex: Int? = nil) {
        let targetIndex: Int?
        if let startIndex {
            targetIndex = startIndex
        } else {
            targetIndex = audioBufferHandlers.indices.last
        }
        guard let index = targetIndex, audioBufferHandlers.indices.contains(index) else { return }
        if debugHandlers.indices.contains(index) {
            debugHandlers[index](.tap(frameLength: buffer.frameLength, sampleRate: sampleRate))
        }
        audioBufferHandlers[index](buffer, sampleRate)
    }

    private static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }
}

private final class RecordingPitchDetector: PitchDetecting {
    private let lock = NSLock()
    private var recordedSampleRates: [Double] = []

    var sampleRates: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSampleRates
    }

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        lock.lock()
        recordedSampleRates.append(sampleRate)
        lock.unlock()
        return nil
    }
}

private final class BlockingPitchDetector: PitchDetecting {
    let firstDetectionStarted = XCTestExpectation(description: "First tuner pitch detection started")

    private let lock = NSLock()
    private let firstDetectionSemaphore = DispatchSemaphore(value: 0)
    private var detectionCount = 0
    private var markers: [Int] = []

    var detectedMarkers: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return markers
    }

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        let marker = Int(samples.first ?? 0)
        let index: Int

        lock.lock()
        detectionCount += 1
        index = detectionCount
        markers.append(marker)
        lock.unlock()

        if index == 1 {
            firstDetectionStarted.fulfill()
            _ = firstDetectionSemaphore.wait(timeout: .now() + 2)
        }

        return Self.result(for: marker)
    }

    func releaseFirstDetection() {
        firstDetectionSemaphore.signal()
    }

    private static func result(for marker: Int) -> PitchDetectionResult {
        switch marker {
        case 3:
            return PitchDetectionResult(
                frequencyHz: 523.25,
                midiNote: 72,
                noteName: "C",
                octave: 5,
                centsOffset: 0,
                confidence: 1,
                rms: 1
            )
        case 2:
            return PitchDetectionResult(
                frequencyHz: 493.88,
                midiNote: 71,
                noteName: "B",
                octave: 4,
                centsOffset: 0,
                confidence: 1,
                rms: 1
            )
        default:
            return PitchDetectionResult(
                frequencyHz: 440,
                midiNote: 69,
                noteName: "A",
                octave: 4,
                centsOffset: 0,
                confidence: 1,
                rms: 1
            )
        }
    }
}

private final class QueuedPitchDetector: PitchDetecting {
    private let lock = NSLock()
    private var results: [PitchDetectionResult?]
    private var callCount = 0

    var detectCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    init(results: [PitchDetectionResult?]) {
        self.results = results
    }

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        lock.lock()
        defer { lock.unlock() }

        callCount += 1
        guard !results.isEmpty else { return nil }
        return results.removeFirst()
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
