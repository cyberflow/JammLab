import XCTest
@testable import JammLab

final class ClickSoundSettingsTests: XCTestCase {
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
