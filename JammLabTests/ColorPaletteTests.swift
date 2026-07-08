import XCTest
@testable import JammLab

final class ColorPaletteTests: XCTestCase {
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
        XCTAssertEqual(palette.hex(for: .notationTrackBackground), "#303030")
        XCTAssertEqual(palette.hex(for: .notationSymbolsAndLines), "#F2F2F2")
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
            AppColorRole.primaryText.rawValue: "#FFFF",
            AppColorRole.notationSymbolsAndLines.rawValue: "#12GG34"
        ])
        defaults.set(try JSONEncoder().encode(invalidPalette), forKey: AppSettingsStore.colorPaletteKey)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.colorPalette.hex(for: .accent), AppColorRole.accent.defaultHex)
        XCTAssertEqual(store.colorPalette.hex(for: .primaryText), AppColorRole.primaryText.defaultHex)
        XCTAssertEqual(store.colorPalette.hex(for: .notationSymbolsAndLines), AppColorRole.notationSymbolsAndLines.defaultHex)
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
        XCTAssertEqual(store.colorPalette.hex(for: .notationTrackBackground), AppColorRole.notationTrackBackground.defaultHex)
        XCTAssertEqual(store.colorPalette.hex(for: .notationSymbolsAndLines), AppColorRole.notationSymbolsAndLines.defaultHex)
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
}
