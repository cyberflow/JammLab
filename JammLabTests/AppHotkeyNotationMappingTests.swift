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
            ("3", 20, .setNotationDurationSixteenth, 16),
            ("4", 21, .setNotationDurationEighth, 8),
            ("5", 23, .setNotationDurationQuarter, 4),
            ("6", 22, .setNotationDurationHalf, 2),
            ("7", 26, .setNotationDurationWhole, 1)
        ]

        for expectation in expectations {
            let event = try keyEvent(key: expectation.key, keyCode: expectation.keyCode)

            XCTAssertEqual(AppHotkey(event: event), expectation.hotkey)
            XCTAssertEqual(expectation.hotkey.key, expectation.key)
            XCTAssertEqual(expectation.hotkey.notationDurationDenominator, expectation.denominator)
            XCTAssertTrue(AppHotkey.notationDurationHotkeys.contains(expectation.hotkey))
        }

        XCTAssertEqual(AppHotkey.setNotationDurationSixteenth.title, "Set Sixteenth Note Duration")
        XCTAssertEqual(AppHotkey.setNotationDurationEighth.title, "Set Eighth Note Duration")
        XCTAssertEqual(
            AppHotkey.setNotationDurationEighth.detail,
            "Set notation duration to eighth notes for the selected notation item."
        )
        XCTAssertTrue(AppHotkey.allCases.contains(.setNotationDurationWhole))
        XCTAssertEqual(
            AppHotkey.notationDurationHotkeys,
            [
                .setNotationDurationSixteenth,
                .setNotationDurationEighth,
                .setNotationDurationQuarter,
                .setNotationDurationHalf,
                .setNotationDurationWhole
            ]
        )
    }

    func testAppHotkeyRecognizesNotationNoteEntryModeToggle() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "n",
            charactersIgnoringModifiers: "n",
            isARepeat: false,
            keyCode: 45
        ))

        XCTAssertEqual(AppHotkey(event: event), .toggleNotationNoteEntryMode)
        XCTAssertEqual(AppHotkey.toggleNotationNoteEntryMode.key, "N")
        XCTAssertEqual(AppHotkey.toggleNotationNoteEntryMode.title, "Notation Note Entry")
        XCTAssertTrue(AppHotkey.allCases.contains(.toggleNotationNoteEntryMode))
    }

    func testAppHotkeyRecognizesNotationNotePitchArrowKeys() throws {
        let upEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F700}",
            charactersIgnoringModifiers: "\u{F700}",
            isARepeat: false,
            keyCode: 126
        ))
        let downEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false,
            keyCode: 125
        ))
        let shiftUpEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F700}",
            charactersIgnoringModifiers: "\u{F700}",
            isARepeat: false,
            keyCode: 126
        ))

        XCTAssertEqual(AppHotkey(event: upEvent), .moveSelectedNotationNotePitchUp)
        XCTAssertEqual(AppHotkey(event: downEvent), .moveSelectedNotationNotePitchDown)
        XCTAssertNil(AppHotkey(event: shiftUpEvent))
        XCTAssertEqual(AppHotkey.moveSelectedNotationNotePitchUp.key, "Arrow Up")
        XCTAssertEqual(AppHotkey.moveSelectedNotationNotePitchDown.key, "Arrow Down")
        XCTAssertEqual(AppHotkey.moveSelectedNotationNotePitchUp.title, "Move Notation Note Up")
        XCTAssertTrue(AppHotkey.allCases.contains(.moveSelectedNotationNotePitchDown))
    }

    func testAppHotkeyRecognizesNotationDurationNumpadKeys() throws {
        let expectations: [(key: String, keyCode: UInt16, hotkey: AppHotkey, denominator: Int)] = [
            ("3", 85, .setNotationDurationSixteenth, 16),
            ("4", 86, .setNotationDurationEighth, 8),
            ("5", 87, .setNotationDurationQuarter, 4),
            ("6", 88, .setNotationDurationHalf, 2),
            ("7", 89, .setNotationDurationWhole, 1)
        ]

        for expectation in expectations {
            let event = try keyEvent(key: expectation.key, keyCode: expectation.keyCode)

            XCTAssertEqual(AppHotkey(event: event), expectation.hotkey)
            XCTAssertEqual(expectation.hotkey.notationDurationDenominator, expectation.denominator)
        }
    }

    func testAppHotkeyRecognizesAugmentationDotFromPeriodAndNumpadDecimal() throws {
        let rowPeriod = try keyEvent(key: ".", keyCode: 47)
        let numpadPeriod = try keyEvent(key: ".", keyCode: 65)
        let numpadComma = try keyEvent(key: ",", keyCode: 65)
        let rowComma = try keyEvent(key: ",", keyCode: 43)

        XCTAssertEqual(AppHotkey(event: rowPeriod), .toggleNotationDurationDot)
        XCTAssertEqual(AppHotkey(event: numpadPeriod), .toggleNotationDurationDot)
        XCTAssertEqual(AppHotkey(event: numpadComma), .toggleNotationDurationDot)
        XCTAssertNil(AppHotkey(event: rowComma))
        XCTAssertEqual(AppHotkey.toggleNotationDurationDot.key, ".; Num.; Num,")
        XCTAssertEqual(AppHotkey.toggleNotationDurationDot.title, "Augmentation dot")
        XCTAssertEqual(AppHotkey.toggleNotationDurationDot.detail, "Toggle duration dot")
        XCTAssertNil(AppHotkey.toggleNotationDurationDot.notationDurationDenominator)
        XCTAssertFalse(AppHotkey.notationDurationHotkeys.contains(.toggleNotationDurationDot))
        XCTAssertTrue(AppHotkey.notationDurationEditingHotkeys.contains(.toggleNotationDurationDot))
    }

    func testAppHotkeyNotationDurationShortcutTextUsesPrimaryAndNumpadKeys() {
        let expectations: [(denominator: Int, shortcutText: String)] = [
            (16, "3; Num3"),
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

        XCTAssertNil(AppHotkey.notationDurationShortcutText(for: 32))
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

    private func keyEvent(
        key: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: isRepeat,
            keyCode: keyCode
        ))
    }
}
