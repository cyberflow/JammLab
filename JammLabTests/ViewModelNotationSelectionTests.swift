import XCTest
@testable import JammLab

final class ViewModelNotationSelectionTests: XCTestCase {
    @MainActor
    func testNotationWindowPartVisibilityCanShowOnlyStemPartButNeverEmpty() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.visibleNotationPartIDs = [.main, .stem(.bass)]

        viewModel.toggleNotationWindowPartVisibility(.main)

        XCTAssertEqual(viewModel.normalizedVisibleNotationPartIDs(), [.stem(.bass)])

        viewModel.toggleNotationWindowPartVisibility(.stem(.bass))

        XCTAssertEqual(viewModel.normalizedVisibleNotationPartIDs(), [.main])
    }

    @MainActor
    func testStemSelectionCannotEditHarmonyAndIsPreservedWhenRequested() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "bass-note",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel, partID: .stem(.bass))
        let item = try XCTUnwrap(measure.notationItems.first { $0.id == "bass-note" })
        let selection = NotationItemSelection(measure: measure, item: item)
        viewModel.selectNotationItem(selection)

        XCTAssertTrue(viewModel.canEditSelectedNotationItem)
        XCTAssertFalse(viewModel.canEditHarmonyAtSelectedNotationItem)
        XCTAssertFalse(viewModel.requestEditSelectedNotationItem())
        XCTAssertEqual(viewModel.selectedNotationItem, selection)
    }

    @MainActor
    func testMainSelectionRemainsEligibleForHarmonyEditing() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))

        XCTAssertTrue(viewModel.canEditHarmonyAtSelectedNotationItem)
        XCTAssertTrue(viewModel.requestEditSelectedNotationItem())
        XCTAssertNotNil(viewModel.pendingHarmonyEditorRequest)
    }

    @MainActor
    func testSelectingNotationMeasureAtCurrentMarkerDoesNotMarkProjectModified() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)

        viewModel.selectNotationMeasure(measure)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertEqual(viewModel.playbackMarkerTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertTrue(viewModel.canCopySelectedNotationMeasure)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationMeasureMovesPlaybackMarkerExactlyToMeasureStart() throws {
        let engine = MockPlaybackEngine()
        let viewModel = try loadedNotationViewModel(duration: 8, playbackEngine: engine)
        viewModel.isSnapEnabled = true
        let measure = try notationMeasure(2, in: viewModel)

        viewModel.selectNotationMeasure(measure)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2])
        XCTAssertEqual(viewModel.playbackMarkerTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationItemDoesNotMarkProjectModifiedAndClearsMeasureSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)

        viewModel.selectNotationMeasure(measure)
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertEqual(viewModel.selectedNotationItem?.measureNumber, 1)
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 0)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationNoteAuditionsWhenRequested() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let pitch = NotationPitch(step: .e, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "selected-note",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        let measure = try notationMeasure(1, in: viewModel)
        let note = try XCTUnwrap(measure.notationItems.first { $0.id == "selected-note" })
        let rest = try XCTUnwrap(measure.notationItems.first { $0.id == "rest" })

        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: note),
            shouldAudition: true
        )
        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: note),
            shouldAudition: true
        )
        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: rest),
            shouldAudition: true
        )
        viewModel.clearNotationItemSelection()

        XCTAssertEqual(auditioner.auditionedPitches, [pitch, pitch])
        XCTAssertEqual(auditioner.auditionedRoutes, [.melodic, .melodic])
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationNoteDoesNotAuditionWhenSuppressed() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "selected-note",
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        let measure = try notationMeasure(1, in: viewModel)
        let note = try XCTUnwrap(measure.notationItems.first { $0.id == "selected-note" })

        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: note),
            shouldAudition: false
        )

        XCTAssertTrue(auditioner.auditionedPitches.isEmpty)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNotationEntryModesAreMutuallyExclusiveAndClearEditingState() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        let harmony = HarmonySymbol(
            time: measure.startTime,
            measureNumber: measure.number,
            offsetInQuarterNotes: 0,
            rawText: "C"
        )
        viewModel.harmonySymbols = [harmony]
        viewModel.selectedNotationMeasures = [NotationMeasureSelection(measure: measure)]
        viewModel.notationMeasureSelectionAnchor = NotationMeasureSelection(measure: measure)
        viewModel.selectedNotationItem = NotationItemSelection(measure: measure, item: item)
        viewModel.selectedHarmonySymbolID = harmony.id
        viewModel.pendingHarmonyEditorRequest = HarmonyEditorRequest(time: measure.startTime)

        viewModel.setNotationNoteEntryModeEnabled(true)

        XCTAssertEqual(viewModel.notationEntryMode, .note)
        XCTAssertTrue(viewModel.isNotationNoteEntryModeEnabled)
        XCTAssertFalse(viewModel.isNotationRestEntryModeEnabled)
        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertNil(viewModel.notationMeasureSelectionAnchor)
        XCTAssertNil(viewModel.selectedNotationItem)
        XCTAssertNil(viewModel.selectedHarmonySymbolID)
        XCTAssertNil(viewModel.pendingHarmonyEditorRequest)

        viewModel.setNotationRestEntryModeEnabled(true)

        XCTAssertEqual(viewModel.notationEntryMode, .rest)
        XCTAssertFalse(viewModel.isNotationNoteEntryModeEnabled)
        XCTAssertTrue(viewModel.isNotationRestEntryModeEnabled)

        viewModel.toggleNotationRestEntryMode()

        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertFalse(viewModel.isNotationEntryModeEnabled)

        viewModel.setNotationNoteEntryModeEnabled(true)
        viewModel.clearNotationEntryMode()

        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertFalse(viewModel.isNotationNoteEntryModeEnabled)
        XCTAssertFalse(viewModel.isNotationRestEntryModeEnabled)
    }

    @MainActor
    func testRequestEditSelectedNotationItemUsesExactItemOffsetAndExistingHarmony() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = NotationMeasureItem(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let harmony = HarmonySymbol(
            time: NotationMeasureTiming.time(forQuarterOffset: 1, in: measure),
            measureNumber: measure.number,
            offsetInQuarterNotes: 1,
            rawText: "Fmaj7"
        )
        viewModel.harmonySymbols = [harmony]
        viewModel.notationItems = [item]
        viewModel.markProjectClean()

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let updatedItem = try XCTUnwrap(updatedMeasure.notationItems.first { $0.offsetInQuarterNotes == 1 })
        viewModel.selectNotationItem(NotationItemSelection(measure: updatedMeasure, item: updatedItem))

        XCTAssertTrue(viewModel.requestEditSelectedNotationItem())
        let request = try XCTUnwrap(viewModel.pendingHarmonyEditorRequest)
        XCTAssertEqual(request.time, harmony.time, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedHarmonySymbolID, harmony.id)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNotationItemSelectionClearsForTempoMapAndUndoChanges() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let firstItem = try XCTUnwrap(firstMeasure.notationItems.first)

        viewModel.selectNotationItem(NotationItemSelection(measure: firstMeasure, item: firstItem))
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertNil(viewModel.selectedNotationItem)

        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let updatedItem = try XCTUnwrap(updatedMeasure.notationItems.first)
        viewModel.markProjectClean()
        viewModel.selectNotationItem(NotationItemSelection(measure: updatedMeasure, item: updatedItem))
        viewModel.addNote(at: 0.5)

        XCTAssertNotNil(viewModel.selectedNotationItem)

        viewModel.undoLastEdit()

        XCTAssertNil(viewModel.selectedNotationItem)
    }

    @MainActor
    func testShiftSelectingNotationMeasuresBuildsContiguousRange() throws {
        let engine = MockPlaybackEngine()
        let viewModel = try loadedNotationViewModel(duration: 10, playbackEngine: engine)
        let secondMeasure = try notationMeasure(2, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)

        viewModel.selectNotationMeasure(secondMeasure)
        viewModel.selectNotationMeasure(fourthMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2, 3, 4])
        XCTAssertEqual(viewModel.playbackMarkerTime, secondMeasure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, secondMeasure.startTime, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, secondMeasure.startTime, accuracy: 0.0001)

        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2])
    }

    @MainActor
    func testReverseShiftSelectingNotationMeasuresMovesMarkerToFirstSelectedMeasure() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)

        viewModel.selectNotationMeasure(thirdMeasure)

        XCTAssertEqual(viewModel.playbackMarkerTime, thirdMeasure.startTime, accuracy: 0.0001)

        viewModel.selectNotationMeasure(firstMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1, 2, 3])
        XCTAssertEqual(viewModel.playbackMarkerTime, firstMeasure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, firstMeasure.startTime, accuracy: 0.0001)
    }

    @MainActor
    func testShiftSelectingNotationMeasureWithoutAnchorFallsBackToSingleSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let secondMeasure = try notationMeasure(2, in: viewModel)

        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2])
    }

    @MainActor
    func testTempoMapChangesClearSelectedNotationMeasure() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)

        viewModel.selectNotationMeasure(measure)
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
    }

    @MainActor
    func testClearingNotationMeasureSelectionDoesNotMovePlaybackMarker() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(2, in: viewModel)
        viewModel.selectNotationMeasure(measure)
        viewModel.markProjectClean()

        viewModel.clearNotationMeasureSelection()

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertEqual(viewModel.playbackMarkerTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testDeletingSelectedMeasureContentsKeepsHarmonySelectionAndSupportsUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let mainNote = NotationMeasureItem(
            id: "main-note",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let mainRest = NotationMeasureItem(
            id: "main-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 3,
            displayDuration: NotationDuration(denominator: 2, isDotted: true)
        )
        let bassNote = NotationMeasureItem(
            id: "bass-note",
            partID: .stem(.bass),
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 2),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1)
        )
        let harmony = HarmonySymbol(
            time: 0,
            measureNumber: 1,
            offsetInQuarterNotes: 0,
            rawText: "Cmaj7"
        )
        viewModel.notationItems = [mainNote, mainRest, bassNote]
        viewModel.harmonySymbols = [harmony]
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.markProjectClean()
        let measure = try notationMeasure(1, in: viewModel)
        viewModel.selectNotationMeasure(measure)

        XCTAssertTrue(viewModel.deleteSelectedNotationMeasureContents())

        XCTAssertEqual(viewModel.notationItems, [bassNote])
        XCTAssertEqual(viewModel.harmonySymbols, [harmony])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertEqual(viewModel.notationMeasureSelectionAnchor?.number, 1)
        let clearedMeasure = try notationMeasure(1, in: viewModel)
        let defaultRest = try XCTUnwrap(clearedMeasure.notationItems.first)
        XCTAssertEqual(clearedMeasure.notationItems.count, 1)
        XCTAssertEqual(defaultRest.kind, .rest)
        XCTAssertEqual(defaultRest.offsetInQuarterNotes, 0)
        XCTAssertEqual(defaultRest.durationInQuarterNotes, 4)
        XCTAssertTrue(defaultRest.isSynthesized)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertEqual(undoManager.undoActionName, "Delete Measure Contents")

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.notationItems, [mainNote, mainRest, bassNote])
        XCTAssertEqual(viewModel.harmonySymbols, [harmony])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        XCTAssertEqual(viewModel.notationItems, [bassNote])
        XCTAssertEqual(viewModel.harmonySymbols, [harmony])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testDeletingSelectedMeasureRangeOnlyClearsSelectedPart() throws {
        let viewModel = try loadedNotationViewModel(duration: 10)
        let mainItems = [
            NotationMeasureItem(
                id: "main-1",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "main-2",
                kind: .note,
                pitch: NotationPitch(step: .d, octave: 4),
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "main-3",
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 4),
                measureNumber: 3,
                measureStartTime: 4,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let bassItems = [
            NotationMeasureItem(
                id: "bass-1",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "bass-2",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .d, octave: 2),
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let harmonies = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 2, measureNumber: 2, offsetInQuarterNotes: 0, rawText: "Dm")
        ]
        viewModel.notationItems = mainItems + bassItems
        viewModel.harmonySymbols = harmonies
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let secondMeasure = try notationMeasure(2, in: viewModel)
        viewModel.selectNotationMeasure(firstMeasure)
        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)

        XCTAssertTrue(viewModel.deleteSelectedNotationMeasureContents())

        XCTAssertEqual(Set(viewModel.notationItems.map(\.id)), ["main-3", "bass-1", "bass-2"])
        XCTAssertEqual(viewModel.harmonySymbols, harmonies)
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1, 2])
        for measureNumber in 1...2 {
            let measure = try notationMeasure(measureNumber, in: viewModel)
            XCTAssertEqual(measure.notationItems.count, 1)
            XCTAssertTrue(try XCTUnwrap(measure.notationItems.first).isSynthesized)
        }
    }

    @MainActor
    func testDeletingSelectedStemMeasureContentsKeepsMainPart() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let mainNote = NotationMeasureItem(
            id: "main-note",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let bassNote = NotationMeasureItem(
            id: "bass-note",
            partID: .stem(.bass),
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 2),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        viewModel.notationItems = [mainNote, bassNote]
        let bassMeasure = try notationMeasure(1, in: viewModel, partID: .stem(.bass))
        viewModel.selectNotationMeasure(bassMeasure, partID: .stem(.bass))

        XCTAssertTrue(viewModel.deleteSelectedNotationMeasureContents())

        XCTAssertEqual(viewModel.notationItems, [mainNote])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.partID), [.stem(.bass)])
        let clearedBassMeasure = try notationMeasure(1, in: viewModel, partID: .stem(.bass))
        XCTAssertEqual(clearedBassMeasure.notationItems.count, 1)
        XCTAssertTrue(try XCTUnwrap(clearedBassMeasure.notationItems.first).isSynthesized)
        let preservedMainMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(preservedMainMeasure.notationItems.first(where: { $0.id == mainNote.id }), mainNote)
    }

    @MainActor
    func testDeletingAlreadyEmptySelectedMeasureIsNoOp() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let measure = try notationMeasure(1, in: viewModel)
        viewModel.selectNotationMeasure(measure)
        viewModel.markProjectClean()

        XCTAssertFalse(viewModel.deleteSelectedNotationMeasureContents())

        XCTAssertTrue(viewModel.notationItems.isEmpty)
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testDeletingMeasureContentsSanitizesTieFromRemainingMeasure() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let source = NotationMeasureItem(
            id: "tie-source",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 3,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            tieTargetItemID: "tie-target"
        )
        let target = NotationMeasureItem(
            id: "tie-target",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 2,
            measureStartTime: 2,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        viewModel.notationItems = [source, target]
        let secondMeasure = try notationMeasure(2, in: viewModel)
        viewModel.selectNotationMeasure(secondMeasure)

        XCTAssertTrue(viewModel.deleteSelectedNotationMeasureContents())

        let remaining = try XCTUnwrap(viewModel.notationItems.first)
        XCTAssertEqual(remaining.id, source.id)
        XCTAssertNil(remaining.tieTargetItemID)
    }

}

extension XCTestCase {
    @MainActor
    func loadedNotationViewModel(
        duration: TimeInterval,
        playbackEngine: MockPlaybackEngine? = nil,
        notationNoteAuditioner: NotationNoteAuditioning? = nil
    ) throws -> AudioPlayerViewModel {
        let audioURL = try temporaryAudioFile(duration: duration)
        let playbackEngine = playbackEngine ?? MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: playbackEngine,
            notationNoteAuditioner: notationNoteAuditioner ?? NoopNotationNoteAuditioner()
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "notation.wav", duration: duration)
        try viewModel.loadImportedAudio(media)
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        viewModel.tempoBPM = 120
        viewModel.applyTempoMapToPlaybackEngine()
        viewModel.markProjectClean()
        return viewModel
    }

    @MainActor
    func notationMeasure(
        _ number: Int,
        in viewModel: AudioPlayerViewModel,
        partID: NotationPartID = .main
    ) throws -> ScoreMeasure {
        let score = NotationViewportFactory().scoreState(
            tempoMap: viewModel.tempoMap,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            isPlaying: viewModel.playbackState == .playing,
            keyName: viewModel.effectiveKeyName,
            clef: viewModel.notationClef(for: partID),
            partID: partID,
            includesHarmonies: partID.isMain,
            notationItems: viewModel.notationItems,
            harmonySymbols: viewModel.harmonySymbols,
            notes: viewModel.notes
        )
        return try XCTUnwrap(score.measures.first { $0.number == number })
    }
}

@MainActor
private final class NoopNotationNoteAuditioner: NotationNoteAuditioning {
    func audition(pitch: NotationPitch, route: NotationNoteAuditionRoute) throws {}
}
