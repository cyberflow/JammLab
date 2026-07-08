import AppKit
import XCTest
@testable import JammLab

final class AppHotkeyNotationDurationEventFilterTests: XCTestCase {
    func testAppHotkeyEventFilterDoesNotStealNotationDurationKeysFromTextRespondersOrUnavailableScopes() throws {
        let durationEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "4",
            charactersIgnoringModifiers: "4",
            isARepeat: false,
            keyCode: 21
        ))
        let repeatDurationEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "4",
            charactersIgnoringModifiers: "4",
            isARepeat: true,
            keyCode: 21
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: durationEvent,
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
}
