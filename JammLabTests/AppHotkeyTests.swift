import AppKit
import XCTest
@testable import JammLab

final class AppHotkeyTests: XCTestCase {
    func testAppHotkeyRecognizesTabForPlaybackModeToggle() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))

        XCTAssertEqual(AppHotkey(event: event), .togglePlaybackMode)
        XCTAssertEqual(AppHotkey.togglePlaybackMode.key, "Tab")
    }

    func testAppHotkeyRecognizesSpaceForPlayStop() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))

        XCTAssertEqual(AppHotkey(event: event), .playPause)
        XCTAssertEqual(AppHotkey.playPause.key, "Space")
        XCTAssertEqual(AppHotkey.playPause.title, "Play / Stop")
        XCTAssertEqual(AppHotkey.playPause.detail, "Start playback from the position marker or stop and return to it.")
    }

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

    func testAppHotkeyMappingsDoNotContainDuplicateKeyLabels() {
        let keys = AppHotkey.allCases.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count)
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

    func testAppHotkeyRecognizesOptionVForVideoWindowToggle() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ))

        XCTAssertEqual(AppHotkey(event: event), .toggleVideoWindow)
        XCTAssertEqual(AppHotkey.toggleVideoWindow.key, "Opt+V")
        XCTAssertEqual(AppHotkey.toggleVideoWindow.title, "Video Window")
        XCTAssertEqual(
            AppHotkey.toggleVideoWindow.detail,
            "Open or close the sidecar video window for the current video project."
        )
    }

    func testAppHotkeyRecognizesShiftCForTempoTimeSignatureMarker() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "C",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))

        XCTAssertEqual(AppHotkey(event: event), .addTempoTimeSignatureMarker)
        XCTAssertEqual(AppHotkey.addTempoTimeSignatureMarker.key, "Shift+C")
        XCTAssertEqual(AppHotkey.addTempoTimeSignatureMarker.title, "Add Tempo / Time Signature Marker")
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
