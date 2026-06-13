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

    func testAppSettingsStoreNormalizesEmptyAudioDeviceUIDs() throws {
        let defaults = try temporaryUserDefaults()
        let settings = AudioDeviceSettings(inputDeviceUID: "   ", outputDeviceUID: "\n")
        defaults.set(try JSONEncoder().encode(settings), forKey: AppSettingsStore.audioDeviceSettingsKey)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.audioDeviceSettings, .defaultValue)
    }

    func testAudioSettingsDeviceLoaderDoesNotReadInputDevicesBeforePermission() {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]
        provider.outputDevicesResult = [
            AudioDeviceInfo(uid: "output-1", name: "Output 1", kind: .output, isDefault: true)
        ]
        let permission = MockAudioInputPermissionProvider(status: .notDetermined)
        let loader = AudioSettingsDeviceLoader(deviceProvider: provider, inputPermissionProvider: permission)

        let result = loader.refreshDevices()

        XCTAssertEqual(provider.inputDevicesCallCount, 0)
        XCTAssertEqual(provider.outputDevicesCallCount, 1)
        XCTAssertEqual(result.inputDevices, [])
        XCTAssertEqual(result.outputDevices.map(\.uid), ["output-1"])
        XCTAssertEqual(result.inputPermissionStatus, .notDetermined)
        XCTAssertEqual(permission.requestAccessCount, 0)
    }

    func testAudioSettingsDeviceLoaderReadsInputDevicesAfterPermission() {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]
        let permission = MockAudioInputPermissionProvider(status: .authorized)
        let loader = AudioSettingsDeviceLoader(deviceProvider: provider, inputPermissionProvider: permission)

        let result = loader.refreshDevices()

        XCTAssertEqual(provider.inputDevicesCallCount, 1)
        XCTAssertEqual(result.inputDevices.map(\.uid), ["input-1"])
        XCTAssertEqual(permission.requestAccessCount, 0)
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

    @MainActor
    func testTunerInputServiceRequestsPermissionOnlyWhenStarted() async throws {
        let defaults = try temporaryUserDefaults()
        let settingsStore = JammLab.AppSettingsStore(defaults: defaults)
        settingsStore.updateAudioInputDeviceUID("input-1")

        let provider = MockAudioDeviceProvider()
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
    }

    @MainActor
    func testTunerInputServiceDoesNotStartEngineWhenPermissionDenied() async throws {
        let settingsStore = JammLab.AppSettingsStore(defaults: try temporaryUserDefaults())
        let provider = MockAudioDeviceProvider()
        let permission = MockAudioInputPermissionProvider(status: .denied)
        let engine = MockTunerInputEngine()
        let service = TunerInputService(
            appSettingsStore: settingsStore,
            audioDeviceProvider: provider,
            inputPermissionProvider: permission,
            inputEngine: engine
        )

        await service.start()

        XCTAssertEqual(permission.requestAccessCount, 0)
        XCTAssertEqual(engine.startDeviceIDs, [])
        XCTAssertEqual(service.errorMessage, TunerInputServiceError.microphonePermissionDenied.localizedDescription)
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

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
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

private final class MockTunerInputEngine: TunerInputEngineControlling {
    var startDeviceIDs: [AudioDeviceID] = []
    var stopCallCount = 0

    func start(
        deviceID: AudioDeviceID,
        bufferSize: AVAudioFrameCount,
        onAudioBuffer: @escaping (AVAudioPCMBuffer, Double) -> Void
    ) throws {
        startDeviceIDs.append(deviceID)
    }

    func stop() {
        stopCallCount += 1
    }
}
