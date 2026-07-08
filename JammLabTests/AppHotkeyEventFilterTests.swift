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

}
