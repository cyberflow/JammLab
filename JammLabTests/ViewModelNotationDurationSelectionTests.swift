import CoreGraphics
import XCTest
@testable import JammLab

final class ViewModelNotationDurationSelectionTests: XCTestCase {
    @MainActor
    func testChangingSelectedWholeRestToQuarterCreatesTwoQuartersAndHalfInFourFour() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        viewModel.markProjectClean()

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationDurationDenominator(4)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [4, 4, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [1, 1, 2])
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 0)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testChangingSelectedWholeRestToHalfInThreeFourCreatesHalfAndQuarter() throws {
        let viewModel = try loadedNotationViewModel(duration: 6)
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        viewModel.markProjectClean()

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationDurationDenominator(2)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [2, 4])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [2, 1])
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testAddingNotationNoteRecomposesRemainingRestsAndCanUndo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first)
        let placement = NotationNotePlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: NotationPitch(step: .e, octave: 4),
            x: 0,
            y: 0
        )
        viewModel.markProjectClean()

        XCTAssertTrue(viewModel.insertNotationNote(placement))

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.kind), [.note, .rest, .rest])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 3])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [1, 2, 1])
        XCTAssertEqual(updatedMeasure.notationItems.first?.pitch, NotationPitch(step: .e, octave: 4))
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 0)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        let undoneMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(undoneMeasure.notationItems.count, 1)
        XCTAssertEqual(undoneMeasure.notationItems.first?.kind, .rest)
    }

    @MainActor
    func testAddingNotationNoteToStemPartDoesNotReplaceMainNotationItems() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "main-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let stemMeasure = try notationMeasure(1, in: viewModel, partID: .stem(.bass))
        let rest = try XCTUnwrap(stemMeasure.notationItems.first)
        let placement = NotationNotePlacement(
            measure: stemMeasure,
            partID: .stem(.bass),
            targetRestID: rest.id,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: NotationPitch(step: .e, octave: 2),
            x: 0,
            y: 0
        )

        XCTAssertTrue(viewModel.insertNotationNote(placement))

        let mainMeasure = try notationMeasure(1, in: viewModel)
        let updatedStemMeasure = try notationMeasure(1, in: viewModel, partID: .stem(.bass))
        XCTAssertNotNil(mainMeasure.notationItems.first { $0.id == "main-note" && $0.partID == .main })
        XCTAssertEqual(updatedStemMeasure.notationItems.first?.partID, .stem(.bass))
        XCTAssertEqual(updatedStemMeasure.notationItems.first?.pitch, NotationPitch(step: .e, octave: 2))
    }

    @MainActor
    func testAddingNotationNoteCanConsumeFollowingRestsFromShortTargetRest() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "first-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 5),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "first-eighth-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            ),
            NotationMeasureItem(
                id: "second-eighth-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1.5,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            ),
            NotationMeasureItem(
                id: "half-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 2,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
        viewModel.markProjectClean()

        let measure = try notationMeasure(1, in: viewModel)
        let targetRest = try XCTUnwrap(measure.notationItems.first { $0.id == "second-eighth-rest" })
        let pitch = NotationPitch(step: .e, octave: 4)
        let placement = NotationNotePlacement(
            measure: measure,
            targetRestID: targetRest.id,
            offsetInQuarterNotes: targetRest.offsetInQuarterNotes,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: pitch,
            x: 0,
            y: 0
        )

        XCTAssertTrue(viewModel.insertNotationNote(placement))

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.kind), [.note, .rest, .note, .rest, .rest])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 1.5, 2.5, 3])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [1, 0.5, 1, 0.5, 1])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [4, 8, 4, 8, 4])
        XCTAssertEqual(updatedMeasure.notationItems[2].pitch, pitch)
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 1.5)

        viewModel.undoLastEdit()

        let undoneMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(undoneMeasure.notationItems.map(\.id), [
            "first-note",
            "first-eighth-rest",
            "second-eighth-rest",
            "half-rest"
        ])
    }

    @MainActor
    func testAddingNotationRestCanConsumeFollowingRestsFromShortTargetRest() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "first-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 5),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "first-eighth-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            ),
            NotationMeasureItem(
                id: "second-eighth-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1.5,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            ),
            NotationMeasureItem(
                id: "half-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 2,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
        viewModel.markProjectClean()

        let measure = try notationMeasure(1, in: viewModel)
        let targetRest = try XCTUnwrap(measure.notationItems.first { $0.id == "second-eighth-rest" })
        let placement = NotationRestPlacement(
            measure: measure,
            targetRestID: targetRest.id,
            offsetInQuarterNotes: targetRest.offsetInQuarterNotes,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            x: 0
        )

        XCTAssertTrue(viewModel.insertNotationRest(placement))

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.kind), [.note, .rest, .rest, .rest, .rest])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 1.5, 2.5, 3])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [1, 0.5, 1, 0.5, 1])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [4, 8, 4, 8, 4])
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 1.5)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        let undoneMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(undoneMeasure.notationItems.map(\.id), [
            "first-note",
            "first-eighth-rest",
            "second-eighth-rest",
            "half-rest"
        ])
    }

    @MainActor
    func testRejectedNotationRestDoesNotConsumeAcrossExistingNoteOrMutateSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "short-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            ),
            NotationMeasureItem(
                id: "blocking-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 5),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1.5,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first { $0.id == "short-rest" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: rest))
        viewModel.markProjectClean()
        let originalItems = viewModel.notationItems
        let originalSelection = viewModel.selectedNotationItem
        let placement = NotationRestPlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: rest.offsetInQuarterNotes,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            x: 0
        )

        XCTAssertFalse(viewModel.insertNotationRest(placement))

        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertEqual(viewModel.selectedNotationItem, originalSelection)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testAddingExactPersistedNotationRestSelectsWithoutDirtyingProject() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "explicit-whole-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 1)
            )
        ]
        viewModel.markProjectClean()
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first)
        let placement = NotationRestPlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1),
            x: 0
        )

        XCTAssertTrue(viewModel.insertNotationRest(placement))

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.id), ["explicit-whole-rest"])
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, "explicit-whole-rest")
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testAddingNotationNotesAtLedgerExtremesUsesResolverPlacementAndRespectsPitchBounds() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let staffTop: CGFloat = 40
        let selectedDuration = NotationDuration(denominator: 4)
        let highY = NotationNotePlacementResolver.yPosition(
            forStaffPosition: NotationPitchMapper.minimumStaffPosition,
            staffTop: staffTop
        )
        let lowY = NotationNotePlacementResolver.yPosition(
            forStaffPosition: NotationPitchMapper.maximumStaffPosition,
            staffTop: staffTop
        )

        let initialMeasure = try notationMeasure(1, in: viewModel)
        let highPlacement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: initialMeasure,
            geometry: geometry,
            point: CGPoint(x: 160, y: highY),
            staffTop: staffTop,
            selectedDuration: selectedDuration
        ))
        XCTAssertEqual(highPlacement.pitch, NotationPitch(step: .d, octave: 6))
        XCTAssertTrue(viewModel.insertNotationNote(highPlacement))

        let measureAfterHighNote = try notationMeasure(1, in: viewModel)
        let highNote = try XCTUnwrap(measureAfterHighNote.notationItems.first {
            $0.pitch == NotationPitch(step: .d, octave: 6)
        })
        viewModel.selectNotationItem(NotationItemSelection(measure: measureAfterHighNote, item: highNote))
        XCTAssertFalse(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: -1))
        XCTAssertTrue(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1))

        let lowPlacement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: measureAfterHighNote,
            geometry: geometry,
            point: CGPoint(x: 70, y: lowY),
            staffTop: staffTop,
            selectedDuration: selectedDuration
        ))
        XCTAssertEqual(lowPlacement.pitch, NotationPitch(step: .g, octave: 3))
        XCTAssertTrue(viewModel.insertNotationNote(lowPlacement))

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let lowNote = try XCTUnwrap(updatedMeasure.notationItems.first {
            $0.pitch == NotationPitch(step: .g, octave: 3)
        })
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, lowNote.id)
        XCTAssertEqual(updatedMeasure.notationItems.filter { $0.kind == .note }.compactMap(\.pitch), [
            NotationPitch(step: .d, octave: 6),
            NotationPitch(step: .g, octave: 3)
        ])
        XCTAssertFalse(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1))
        XCTAssertTrue(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: -1))
    }

    @MainActor
    func testAddingNotationNoteAuditionsInsertedPitch() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first)
        let pitch = NotationPitch(step: .g, octave: 4)
        let placement = NotationNotePlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: pitch,
            x: 0,
            y: 0
        )

        XCTAssertTrue(viewModel.insertNotationNote(placement))

        XCTAssertEqual(auditioner.auditionedPitches, [pitch])
    }

    @MainActor
    func testRejectedNotationNoteDoesNotAuditionPitch() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first)
        let placement = NotationNotePlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 8,
            displayDuration: NotationDuration(denominator: 1),
            pitch: NotationPitch(step: .g, octave: 4),
            x: 0,
            y: 0
        )

        XCTAssertFalse(viewModel.insertNotationNote(placement))

        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
        XCTAssertTrue(auditioner.auditionedPitches.isEmpty)
    }

    @MainActor
    func testRejectedNotationNoteDoesNotConsumeAcrossExistingNoteOrAudition() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "short-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            ),
            NotationMeasureItem(
                id: "blocking-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 5),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1.5,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first { $0.id == "short-rest" })
        let placement = NotationNotePlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: rest.offsetInQuarterNotes,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: NotationPitch(step: .g, octave: 4),
            x: 0,
            y: 0
        )

        XCTAssertFalse(viewModel.insertNotationNote(placement))
        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNotationNoteInsertionSucceedsWhenAuditionFails() throws {
        let auditioner = MockNotationNoteAuditioner()
        auditioner.errorToThrow = NotationNoteAuditionerError.initializationFailed
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first)
        let pitch = NotationPitch(step: .a, octave: 4)
        let placement = NotationNotePlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: pitch,
            x: 0,
            y: 0
        )

        XCTAssertTrue(viewModel.insertNotationNote(placement))

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.first?.kind, .note)
        XCTAssertEqual(auditioner.attemptedPitches, [pitch])
        XCTAssertTrue(auditioner.auditionedPitches.isEmpty)
    }

    @MainActor
    func testChangingSelectedNotationNotePitchPreservesRhythmAndCanUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let insertedPitch = NotationPitch(step: .e, octave: 4)
        let updatedPitch = NotationPitch(step: .g, octave: 4)
        let insertedNote = try insertQuarterNote(
            pitch: insertedPitch,
            inMeasure: 1,
            viewModel: viewModel
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.markProjectClean()

        XCTAssertTrue(viewModel.changeSelectedNotationNotePitch(to: updatedPitch))

        let changedNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(changedNote.id, insertedNote.id)
        XCTAssertEqual(changedNote.kind, .note)
        XCTAssertEqual(changedNote.pitch, updatedPitch)
        XCTAssertEqual(changedNote.offsetInQuarterNotes, insertedNote.offsetInQuarterNotes)
        XCTAssertEqual(changedNote.durationInQuarterNotes, insertedNote.durationInQuarterNotes)
        XCTAssertEqual(changedNote.displayDuration, insertedNote.displayDuration)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, insertedNote.id)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        let undoneNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(undoneNote.id, insertedNote.id)
        XCTAssertEqual(undoneNote.pitch, insertedPitch)

        viewModel.redoLastEdit()

        let redoneNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(redoneNote.id, insertedNote.id)
        XCTAssertEqual(redoneNote.pitch, updatedPitch)
    }

    @MainActor
    func testChangingSelectedNotationNotePitchAuditionsDirectCommitOnly() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let insertedPitch = NotationPitch(step: .e, octave: 4)
        let updatedPitch = NotationPitch(step: .a, octave: 4)
        _ = try insertQuarterNote(
            pitch: insertedPitch,
            inMeasure: 1,
            viewModel: viewModel
        )

        XCTAssertTrue(viewModel.changeSelectedNotationNotePitch(to: updatedPitch))

        XCTAssertEqual(auditioner.auditionedPitches, [insertedPitch, updatedPitch])
    }

    @MainActor
    func testChangingSelectedNotationNoteDurationPreservesPitchAndCanUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let insertedPitch = NotationPitch(step: .e, octave: 4)
        let insertedNote = try insertQuarterNote(
            pitch: insertedPitch,
            inMeasure: 1,
            viewModel: viewModel
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.markProjectClean()

        viewModel.setNotationDurationDenominator(2)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let updatedNote = try XCTUnwrap(updatedMeasure.notationItems.first)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.kind), [.note, .rest])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [2, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [2, 2])
        XCTAssertEqual(updatedNote.id, insertedNote.id)
        XCTAssertEqual(updatedNote.pitch, insertedPitch)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, insertedNote.id)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        let undoneNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(undoneNote.id, insertedNote.id)
        XCTAssertEqual(undoneNote.pitch, insertedPitch)
        XCTAssertEqual(undoneNote.durationInQuarterNotes, insertedNote.durationInQuarterNotes)

        viewModel.redoLastEdit()

        let redoneNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(redoneNote.id, insertedNote.id)
        XCTAssertEqual(redoneNote.pitch, insertedPitch)
        XCTAssertEqual(redoneNote.durationInQuarterNotes, 2)
    }

    @MainActor
    func testChangingSelectedNotationNotePitchByStaffStepPreservesRhythmAndCanUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let insertedPitch = NotationPitch(step: .c, octave: 5)
        let updatedPitch = NotationPitch(step: .b, octave: 4)
        let insertedNote = try insertQuarterNote(
            pitch: insertedPitch,
            inMeasure: 1,
            viewModel: viewModel
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.markProjectClean()

        XCTAssertTrue(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1))
        XCTAssertTrue(viewModel.changeSelectedNotationNotePitch(byStaffPositionDelta: 1))

        let changedNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(changedNote.id, insertedNote.id)
        XCTAssertEqual(changedNote.pitch, updatedPitch)
        XCTAssertEqual(changedNote.offsetInQuarterNotes, insertedNote.offsetInQuarterNotes)
        XCTAssertEqual(changedNote.durationInQuarterNotes, insertedNote.durationInQuarterNotes)

        viewModel.undoLastEdit()

        let undoneNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(undoneNote.id, insertedNote.id)
        XCTAssertEqual(undoneNote.pitch, insertedPitch)

        viewModel.redoLastEdit()

        let redoneNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(redoneNote.id, insertedNote.id)
        XCTAssertEqual(redoneNote.pitch, updatedPitch)
    }

    @MainActor
    func testChangingSelectedNotationNotePitchByStaffStepUpAuditionsAdjacentPitch() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let insertedPitch = NotationPitch(step: .c, octave: 5)
        let updatedPitch = NotationPitch(step: .d, octave: 5)
        _ = try insertQuarterNote(
            pitch: insertedPitch,
            inMeasure: 1,
            viewModel: viewModel
        )

        XCTAssertTrue(viewModel.changeSelectedNotationNotePitch(byStaffPositionDelta: -1))

        let changedNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(changedNote.pitch, updatedPitch)
        XCTAssertEqual(auditioner.auditionedPitches, [insertedPitch, updatedPitch])
    }

    @MainActor
    func testChangingSelectedNotationNotePitchNoOpsForRestAndSamePitch() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let note = try insertQuarterNote(
            pitch: NotationPitch(step: .e, octave: 4),
            inMeasure: 1,
            viewModel: viewModel
        )
        viewModel.markProjectClean()

        XCTAssertFalse(viewModel.changeSelectedNotationNotePitch(to: try XCTUnwrap(note.pitch)))
        XCTAssertFalse(viewModel.isProjectModified)

        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first { $0.kind == .rest })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: rest))

        XCTAssertFalse(viewModel.changeSelectedNotationNotePitch(to: NotationPitch(step: .g, octave: 4)))
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testChangingSelectedNotationNotePitchByStaffStepNoOpsForRestBoundsAndUnmappedPitch() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let note = try insertQuarterNote(
            pitch: NotationPitch(step: .d, octave: 6),
            inMeasure: 1,
            viewModel: viewModel
        )
        viewModel.markProjectClean()

        XCTAssertFalse(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: -1))
        XCTAssertFalse(viewModel.changeSelectedNotationNotePitch(byStaffPositionDelta: -1))
        XCTAssertFalse(viewModel.isProjectModified)

        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first { $0.id != note.id })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: rest))

        XCTAssertFalse(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1))
        XCTAssertFalse(viewModel.changeSelectedNotationNotePitch(byStaffPositionDelta: 1))
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: note))
        XCTAssertTrue(viewModel.changeSelectedNotationNotePitch(to: NotationPitch(step: .c, octave: 3)))
        viewModel.markProjectClean()

        XCTAssertFalse(viewModel.canChangeSelectedNotationNotePitch(byStaffPositionDelta: 1))
        XCTAssertFalse(viewModel.changeSelectedNotationNotePitch(byStaffPositionDelta: 1))
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testDeletingSelectedNotationNoteReplacesItWithCorrespondingRestAndCanUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let note = try insertQuarterNote(
            pitch: NotationPitch(step: .e, octave: 4),
            inMeasure: 1,
            viewModel: viewModel
        )
        let harmony = HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C")
        viewModel.harmonySymbols = [harmony]
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.markProjectClean()

        XCTAssertTrue(viewModel.deleteSelectedNotationNote())

        let deletedMeasure = try notationMeasure(1, in: viewModel)
        let replacement = try XCTUnwrap(deletedMeasure.notationItems.first)
        XCTAssertEqual(replacement.id, note.id)
        XCTAssertEqual(replacement.kind, .rest)
        XCTAssertNil(replacement.pitch)
        XCTAssertEqual(replacement.offsetInQuarterNotes, note.offsetInQuarterNotes)
        XCTAssertEqual(replacement.durationInQuarterNotes, note.durationInQuarterNotes)
        XCTAssertEqual(replacement.displayDuration, note.displayDuration)
        XCTAssertEqual(deletedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 3])
        XCTAssertEqual(viewModel.harmonySymbols, [harmony])
        XCTAssertNil(viewModel.selectedNotationItem)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        let undoneNote = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(undoneNote.id, note.id)
        XCTAssertEqual(undoneNote.kind, .note)
        XCTAssertEqual(undoneNote.pitch, note.pitch)

        viewModel.redoLastEdit()

        let redoneRest = try XCTUnwrap(try notationMeasure(1, in: viewModel).notationItems.first)
        XCTAssertEqual(redoneRest.id, note.id)
        XCTAssertEqual(redoneRest.kind, .rest)
    }

    @MainActor
    func testEnablingRestEntryModeReplacesSelectedNoteWithoutChangingOtherMeasureItems() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let selectedNote = NotationMeasureItem(
            id: "selected-eighth-note",
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 0.5,
            displayDuration: NotationDuration(denominator: 8)
        )
        let otherItems = [
            NotationMeasureItem(
                id: "eighth-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0.5,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            ),
            NotationMeasureItem(
                id: "other-quarter-note",
                kind: .note,
                pitch: NotationPitch(step: .g, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "half-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 2,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
        viewModel.notationItems = [selectedNote] + otherItems
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let measure = try notationMeasure(1, in: viewModel)
        let selectedItem = try XCTUnwrap(
            measure.notationItems.first { $0.id == selectedNote.id }
        )
        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: selectedItem),
            shouldAudition: false
        )
        viewModel.markProjectClean()

        viewModel.toggleNotationRestEntryMode()

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let replacementRest = try XCTUnwrap(
            updatedMeasure.notationItems.first { $0.id == selectedNote.id }
        )
        XCTAssertEqual(replacementRest.kind, .rest)
        XCTAssertNil(replacementRest.pitch)
        XCTAssertEqual(replacementRest.offsetInQuarterNotes, selectedNote.offsetInQuarterNotes)
        XCTAssertEqual(replacementRest.durationInQuarterNotes, selectedNote.durationInQuarterNotes)
        XCTAssertEqual(replacementRest.displayDuration, selectedNote.displayDuration)
        XCTAssertEqual(
            updatedMeasure.notationItems.filter { $0.id != selectedNote.id },
            otherItems
        )
        XCTAssertEqual(viewModel.notationEntryMode, .rest)
        XCTAssertNil(viewModel.selectedNotationItem)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undoLastEdit()

        let restoredMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(
            restoredMeasure.notationItems.first { $0.id == selectedNote.id },
            selectedNote
        )
        XCTAssertEqual(
            restoredMeasure.notationItems.filter { $0.id != selectedNote.id },
            otherItems
        )
    }

    @MainActor
    func testEnablingRestEntryModePreservesSynthesizedNeighboringRests() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let note = NotationMeasureItem(
            id: "explicit-quarter-note",
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        viewModel.notationItems = [note]
        let measureBeforeConversion = try notationMeasure(1, in: viewModel)
        let selectedNote = try XCTUnwrap(
            measureBeforeConversion.notationItems.first { $0.id == note.id }
        )
        let synthesizedNeighbors = measureBeforeConversion.notationItems.filter {
            $0.id != note.id
        }
        XCTAssertFalse(synthesizedNeighbors.isEmpty)
        XCTAssertTrue(synthesizedNeighbors.allSatisfy(\.isSynthesized))
        viewModel.selectNotationItem(
            NotationItemSelection(measure: measureBeforeConversion, item: selectedNote),
            shouldAudition: false
        )

        viewModel.toggleNotationRestEntryMode()

        let convertedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(
            convertedMeasure.notationItems.filter { $0.id != note.id },
            synthesizedNeighbors
        )
        XCTAssertEqual(
            convertedMeasure.notationItems.first { $0.id == note.id }?.kind,
            .rest
        )
    }

    @MainActor
    func testDeletingSelectedNotationRestIsNoOp() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let note = try insertQuarterNote(
            pitch: NotationPitch(step: .e, octave: 4),
            inMeasure: 1,
            viewModel: viewModel
        )
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first { $0.id != note.id })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: rest))
        viewModel.markProjectClean()

        XCTAssertFalse(viewModel.deleteSelectedNotationNote())

        let unchangedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(unchangedMeasure.notationItems.first(where: { $0.id == rest.id })?.kind, .rest)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNoteEntryDurationChangeDoesNotEditSelectedItem() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationNoteEntryModeEnabled(true)
        viewModel.setNotationDurationDenominator(4)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(viewModel.notationDurationDenominator, 4)
        XCTAssertNil(viewModel.selectedNotationItem)
        XCTAssertEqual(updatedMeasure.notationItems.count, 1)
        XCTAssertEqual(updatedMeasure.notationItems.first?.displayDuration.denominator, 1)
    }

    @MainActor
    func testRestEntryDurationChangeDoesNotEditSelectedItem() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationRestEntryModeEnabled(true)
        viewModel.setNotationDurationDenominator(4)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(viewModel.notationDurationDenominator, 4)
        XCTAssertNil(viewModel.selectedNotationItem)
        XCTAssertEqual(updatedMeasure.notationItems.count, 1)
        XCTAssertEqual(updatedMeasure.notationItems.first?.displayDuration.denominator, 1)
    }

    @MainActor
    private func insertQuarterNote(
        pitch: NotationPitch,
        inMeasure measureNumber: Int,
        viewModel: AudioPlayerViewModel
    ) throws -> NotationMeasureItem {
        let measure = try notationMeasure(measureNumber, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first)
        let placement = NotationNotePlacement(
            measure: measure,
            targetRestID: rest.id,
            offsetInQuarterNotes: rest.offsetInQuarterNotes,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: pitch,
            x: 0,
            y: 0
        )
        XCTAssertTrue(viewModel.insertNotationNote(placement))
        return try XCTUnwrap(try notationMeasure(measureNumber, in: viewModel).notationItems.first)
    }
}
