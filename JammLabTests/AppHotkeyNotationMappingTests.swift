import AppKit
import XCTest
@testable import JammLab

final class AppHotkeyNotationMappingTests: XCTestCase {
    func testAppHotkeyExposesSelectedNotationItemHarmonyShortcutMetadata() {
        XCTAssertTrue(AppHotkey.allCases.contains(.editHarmonyAtSelectedNotationItem))
        XCTAssertEqual(AppHotkey.editHarmonyAtSelectedNotationItem.key, "Cmd+K")
        XCTAssertEqual(AppHotkey.editHarmonyAtSelectedNotationItem.title, "Edit Harmony")
        XCTAssertEqual(
            AppHotkey.editHarmonyAtSelectedNotationItem.detail,
            "Open harmony entry for the selected notation item."
        )
    }

    func testAppHotkeyRecognizesNotationDurationNumberKeys() throws {
        let expectations: [(key: String, keyCode: UInt16, hotkey: AppHotkey, denominator: Int)] = [
            ("4", 21, .setNotationDurationEighth, 8),
            ("5", 23, .setNotationDurationQuarter, 4),
            ("6", 22, .setNotationDurationHalf, 2),
            ("7", 26, .setNotationDurationWhole, 1)
        ]

        for expectation in expectations {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: expectation.key,
                charactersIgnoringModifiers: expectation.key,
                isARepeat: false,
                keyCode: expectation.keyCode
            ))

            XCTAssertEqual(AppHotkey(event: event), expectation.hotkey)
            XCTAssertEqual(expectation.hotkey.key, expectation.key)
            XCTAssertEqual(expectation.hotkey.notationDurationDenominator, expectation.denominator)
            XCTAssertTrue(AppHotkey.notationDurationHotkeys.contains(expectation.hotkey))
        }

        XCTAssertEqual(AppHotkey.setNotationDurationEighth.title, "Set Eighth Note Duration")
        XCTAssertEqual(
            AppHotkey.setNotationDurationEighth.detail,
            "Set notation duration to eighth notes for the selected notation item."
        )
        XCTAssertTrue(AppHotkey.allCases.contains(.setNotationDurationWhole))
    }

    func testAppHotkeyRecognizesNotationDurationNumpadKeys() throws {
        let expectations: [(key: String, keyCode: UInt16, hotkey: AppHotkey, denominator: Int)] = [
            ("4", 86, .setNotationDurationEighth, 8),
            ("5", 87, .setNotationDurationQuarter, 4),
            ("6", 88, .setNotationDurationHalf, 2),
            ("7", 89, .setNotationDurationWhole, 1)
        ]

        for expectation in expectations {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: expectation.key,
                charactersIgnoringModifiers: expectation.key,
                isARepeat: false,
                keyCode: expectation.keyCode
            ))

            XCTAssertEqual(AppHotkey(event: event), expectation.hotkey)
            XCTAssertEqual(expectation.hotkey.notationDurationDenominator, expectation.denominator)
        }
    }

    func testAppHotkeyNotationDurationShortcutTextUsesPrimaryAndNumpadKeys() {
        let expectations: [(denominator: Int, shortcutText: String)] = [
            (8, "4; Num4"),
            (4, "5; Num5"),
            (2, "6; Num6"),
            (1, "7; Num7")
        ]

        for expectation in expectations {
            XCTAssertEqual(
                AppHotkey.notationDurationShortcutText(for: expectation.denominator),
                expectation.shortcutText
            )
        }

        XCTAssertNil(AppHotkey.notationDurationShortcutText(for: 16))
    }

    func testAppHotkeyRecognizesCmdKButNotOldHarmonyKeys() throws {
        let aEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        let hEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "h",
            charactersIgnoringModifiers: "h",
            isARepeat: false,
            keyCode: 4
        ))
        let commandAEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        let commandKEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        ))
        let shiftAEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "A",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))

        XCTAssertNil(AppHotkey(event: aEvent))
        XCTAssertNil(AppHotkey(event: hEvent))
        XCTAssertNil(AppHotkey(event: commandAEvent))
        XCTAssertEqual(AppHotkey(event: commandKEvent), .editHarmonyAtSelectedNotationItem)
        XCTAssertNil(AppHotkey(event: shiftAEvent))
    }

    func testAppHotkeyRecognizesCommandCAndVForNotationMeasureCopyPaste() throws {
        let copyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))
        let pasteEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ))

        XCTAssertEqual(AppHotkey(event: copyEvent), .copyMeasure)
        XCTAssertEqual(AppHotkey.copyMeasure.key, "Cmd+C")
        XCTAssertEqual(AppHotkey.copyMeasure.title, "Copy Measure")
        XCTAssertEqual(AppHotkey(event: pasteEvent), .pasteMeasure)
        XCTAssertEqual(AppHotkey.pasteMeasure.key, "Cmd+V")
        XCTAssertEqual(AppHotkey.pasteMeasure.title, "Paste Measure")
    }

    func testAppHotkeyRecognizesEscapeForNotationMeasureSelectionClear() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        XCTAssertEqual(AppHotkey(event: event), .clearNotationMeasureSelection)
        XCTAssertEqual(AppHotkey.clearNotationMeasureSelection.key, "Esc")
        XCTAssertEqual(AppHotkey.clearNotationMeasureSelection.title, "Clear Measure Selection")
    }
}
