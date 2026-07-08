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

    func testAppHotkeyMappingsDoNotContainDuplicateKeyLabels() {
        let keys = AppHotkey.allCases.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count)
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

}
