import AppKit
import XCTest
@testable import JammLab

final class AppHotkeyNotationDurationEventFilterTests: XCTestCase {
    func testAppHotkeyEventFilterDoesNotStealNotationDurationKeysFromTextRespondersOrUnavailableScopes() throws {
        let durationEvent = try keyEvent(key: "4", keyCode: 21)
        let repeatDurationEvent = try keyEvent(key: "4", keyCode: 21, isRepeat: true)

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: durationEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: AppHotkey.notationDurationHotkeys
            ),
            .setNotationDurationEighth
        )

        let numpadDurationEvent = try keyEvent(key: "4", keyCode: 86, modifierFlags: [.numericPad])
        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: numpadDurationEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: AppHotkey.notationDurationHotkeys
            ),
            .setNotationDurationEighth
        )

        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: durationEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: durationEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: AppHotkey.notationDurationHotkeys
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: durationEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: AppHotkey.notationDurationHotkeys
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: repeatDurationEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: AppHotkey.notationDurationHotkeys
            )
        )
    }

    func testAppHotkeyEventFilterHandlesSixteenthDurationFromNumberRowAndNumpad() throws {
        let numberRowEvent = try keyEvent(key: "3", keyCode: 20)
        let numpadEvent = try keyEvent(key: "3", keyCode: 85, modifierFlags: [.numericPad])

        for event in [numberRowEvent, numpadEvent] {
            XCTAssertEqual(
                AppHotkeyEventFilter.hotkey(
                    for: event,
                    attachedWindowNumber: 42,
                    firstResponder: nil,
                    allowedHotkeys: AppHotkey.notationDurationHotkeys
                ),
                .setNotationDurationSixteenth
            )
        }
    }

    func testAppHotkeyEventFilterScopesAugmentationDotToDurationEditing() throws {
        let event = try keyEvent(key: ".", keyCode: 47)

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: event,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: AppHotkey.notationDurationEditingHotkeys
            ),
            .toggleNotationDurationDot
        )
        XCTAssertNil(AppHotkeyEventFilter.hotkey(
            for: event,
            attachedWindowNumber: 42,
            firstResponder: nil,
            allowedHotkeys: AppHotkey.notationDurationHotkeys
        ))
        XCTAssertNil(AppHotkeyEventFilter.hotkey(
            for: event,
            attachedWindowNumber: 42,
            firstResponder: NSTextView(),
            allowedHotkeys: AppHotkey.notationDurationEditingHotkeys
        ))
    }

    func testAppHotkeyEventFilterScopesAccidentalsWithoutStealingTextInputOrRepeats() throws {
        let events: [(NSEvent, AppHotkey)] = [
            (try keyEvent(key: "-", keyCode: 27), .setNotationAccidentalFlat),
            (try keyEvent(key: "=", keyCode: 24), .setNotationAccidentalNatural),
            (
                try keyEvent(key: "+", keyCode: 24, modifierFlags: [.shift]),
                .setNotationAccidentalSharp
            )
        ]

        for (event, expectedHotkey) in events {
            XCTAssertEqual(
                AppHotkeyEventFilter.hotkey(
                    for: event,
                    attachedWindowNumber: 42,
                    firstResponder: nil,
                    allowedHotkeys: AppHotkey.notationAccidentalHotkeys
                ),
                expectedHotkey
            )
            XCTAssertNil(AppHotkeyEventFilter.hotkey(
                for: event,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: AppHotkey.notationAccidentalHotkeys
            ))
            XCTAssertNil(AppHotkeyEventFilter.hotkey(
                for: event,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            ))
        }

        let repeatedFlat = try keyEvent(key: "-", keyCode: 27, isRepeat: true)
        XCTAssertNil(AppHotkeyEventFilter.hotkey(
            for: repeatedFlat,
            attachedWindowNumber: 42,
            firstResponder: nil,
            allowedHotkeys: AppHotkey.notationAccidentalHotkeys
        ))
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
            windowNumber: 42,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: isRepeat,
            keyCode: keyCode
        ))
    }
}
