import AppKit
import XCTest
@testable import JammLab

final class AppHotkeyEventFilterTests: XCTestCase {
    func testAppHotkeyEventFilterScopesAllowedHotkeysToAttachedWindow() throws {
        let spaceEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        let repeatSpaceEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: true,
            keyCode: 49
        ))
        let tabEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            ),
            .playPause
        )
        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: NSView(),
                allowedHotkeys: [.playPause]
            ),
            .playPause
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: spaceEvent,
                attachedWindowNumber: 7,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: repeatSpaceEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: tabEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
    }

    func testAppHotkeyEventFilterDoesNotStealMeasureCopyPasteFromTextRespondersOrUnavailableScopes() throws {
        let copyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.copyMeasure]
            ),
            .copyMeasure
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.copyMeasure]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: copyEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.copyMeasure]
            )
        )
    }

    func testAppHotkeyEventFilterDoesNotStealEscapeFromTextRespondersOrUnavailableScopes() throws {
        let escapeEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.clearNotationMeasureSelection]
            ),
            .clearNotationMeasureSelection
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.clearNotationMeasureSelection]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: escapeEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.clearNotationMeasureSelection]
            )
        )
    }

    func testAppHotkeyEventFilterDoesNotStealEditHarmonyFromTextRespondersOrUnavailableScopes() throws {
        let editHarmonyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        ))
        let repeatEditHarmonyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: true,
            keyCode: 40
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: editHarmonyEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.editHarmonyAtSelectedNotationItem]
            ),
            .editHarmonyAtSelectedNotationItem
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: editHarmonyEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: editHarmonyEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.editHarmonyAtSelectedNotationItem]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: editHarmonyEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.editHarmonyAtSelectedNotationItem]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: repeatEditHarmonyEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.editHarmonyAtSelectedNotationItem]
            )
        )
    }

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
