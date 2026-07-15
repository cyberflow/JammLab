import XCTest
@testable import JammLab

final class AppSettingsStoreTests: XCTestCase {
    func testAppSettingsStoreDefaultsAndClampsRestoredClickVolume() throws {
        let defaults = try temporaryUserDefaults()
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.restoredClickVolume(), AppSliderDefaults.clickVolume)

        defaults.set(1.5, forKey: AppSettingsStore.clickVolumeKey)
        XCTAssertEqual(store.restoredClickVolume(), 1)

        defaults.set(-0.5, forKey: AppSettingsStore.clickVolumeKey)
        XCTAssertEqual(store.restoredClickVolume(), 0)
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
}
