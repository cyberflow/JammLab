import AppKit
import XCTest
@testable import JammLab

final class AppHotkeyNotationEventFilterTests: XCTestCase {
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

    func testAppHotkeyEventFilterDoesNotStealNotationPitchArrowsFromTextRespondersOrUnavailableScopes() throws {
        let arrowEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "\u{F700}",
            charactersIgnoringModifiers: "\u{F700}",
            isARepeat: false,
            keyCode: 126
        ))
        let repeatArrowEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "\u{F700}",
            charactersIgnoringModifiers: "\u{F700}",
            isARepeat: true,
            keyCode: 126
        ))

        XCTAssertEqual(
            AppHotkeyEventFilter.hotkey(
                for: arrowEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.moveSelectedNotationNotePitchUp]
            ),
            .moveSelectedNotationNotePitchUp
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: arrowEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.playPause]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: arrowEvent,
                attachedWindowNumber: 42,
                firstResponder: NSTextView(),
                allowedHotkeys: [.moveSelectedNotationNotePitchUp]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: arrowEvent,
                attachedWindowNumber: 42,
                firstResponder: AbletonNumberFieldNSView(),
                allowedHotkeys: [.moveSelectedNotationNotePitchUp]
            )
        )
        XCTAssertNil(
            AppHotkeyEventFilter.hotkey(
                for: repeatArrowEvent,
                attachedWindowNumber: 42,
                firstResponder: nil,
                allowedHotkeys: [.moveSelectedNotationNotePitchUp]
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

    func testTieHotkeyRequiresAvailableScopeAndDoesNotStealTextOrRepeatEvents() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 17
        ))
        let repeatEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: true,
            keyCode: 17
        ))

        XCTAssertEqual(AppHotkeyEventFilter.hotkey(
            for: event,
            attachedWindowNumber: 42,
            firstResponder: nil,
            allowedHotkeys: [.addTiedNotationNote]
        ), .addTiedNotationNote)
        XCTAssertNil(AppHotkeyEventFilter.hotkey(
            for: event,
            attachedWindowNumber: 42,
            firstResponder: nil,
            allowedHotkeys: [.playPause]
        ))
        XCTAssertNil(AppHotkeyEventFilter.hotkey(
            for: event,
            attachedWindowNumber: 42,
            firstResponder: NSTextView(),
            allowedHotkeys: [.addTiedNotationNote]
        ))
        XCTAssertNil(AppHotkeyEventFilter.hotkey(
            for: repeatEvent,
            attachedWindowNumber: 42,
            firstResponder: nil,
            allowedHotkeys: [.addTiedNotationNote]
        ))
    }

    func testHotkeyMonitorConsumesTieOnlyWhenHandlerReportsItHandled() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 17
        ))
        let monitor = AppHotkeyMonitorNSView()
        monitor.onHotkey = { _ in false }

        XCTAssertIdentical(
            monitor.eventAfterHandling(event, hotkey: .addTiedNotationNote),
            event
        )

        monitor.onHotkey = { _ in true }
        XCTAssertNil(monitor.eventAfterHandling(event, hotkey: .addTiedNotationNote))
    }

    @MainActor
    func testHotkeyMonitorConsumesBlockedTieCommandWithoutMutatingNotation() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "blocker",
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let source = try XCTUnwrap(measure.notationItems.first { $0.id == "source" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: source))
        viewModel.markProjectClean()
        let originalItems = viewModel.notationItems
        let originalSelection = viewModel.selectedNotationItem
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 42,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 17
        ))
        let monitor = AppHotkeyMonitorNSView()
        monitor.onHotkey = { hotkey in
            hotkey == .addTiedNotationNote
                && viewModel.handleAddTiedNotationNoteCommand()
        }

        XCTAssertEqual(viewModel.tieCommandStatus, .blocked(.noFreeFollowingDuration))
        XCTAssertNil(monitor.eventAfterHandling(event, hotkey: .addTiedNotationNote))
        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertEqual(viewModel.selectedNotationItem, originalSelection)
        XCTAssertFalse(viewModel.isProjectModified)
    }

}
