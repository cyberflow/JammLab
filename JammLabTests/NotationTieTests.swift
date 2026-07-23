import Foundation
import XCTest
@testable import JammLab

final class NotationTiePlannerTests: XCTestCase {
    func testPlannerCreatesSamePitchContinuationAndLinksSource() throws {
        let pitch = NotationPitch(step: .c, octave: 4)
        let measures = scoreMeasures(
            duration: 4,
            notationItems: [
                note(id: "source", pitch: pitch, measure: 1, start: 0, offset: 0, duration: 1),
                rest(id: "rest", measure: 1, start: 0, offset: 1, duration: 3)
            ]
        )

        let plan = try XCTUnwrap(NotationNoteInsertionPlanner.plan(
            in: measures,
            sourceItemID: "source",
            selectedDuration: NotationDuration(denominator: 4)
        ))
        let replacementItems = plan.replacements.flatMap(\.items)
        let source = try XCTUnwrap(replacementItems.first { $0.id == "source" })
        let target = try XCTUnwrap(replacementItems.first { $0.id == plan.finalItemID })

        XCTAssertEqual(source.tieTargetItemID, target.id)
        XCTAssertEqual(target.pitch, pitch)
        XCTAssertEqual(target.offsetInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(target.durationInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertNil(target.tieTargetItemID)
    }

    func testPlannerSplitsDottedSixteenthAcrossBarlineUsingInternalThirtySecond() throws {
        let pitch = NotationPitch(step: .e, octave: 4)
        let measures = scoreMeasures(
            duration: 8,
            notationItems: [
                note(id: "source", pitch: pitch, measure: 1, start: 0, offset: 3.625, duration: 0.25),
                rest(id: "tail", measure: 1, start: 0, offset: 3.875, duration: 0.125, denominator: 32)
            ]
        )

        let plan = try XCTUnwrap(NotationNoteInsertionPlanner.plan(
            in: measures,
            sourceItemID: "source",
            selectedDuration: NotationDuration(denominator: 16, isDotted: true)
        ))
        let inserted = plan.replacements
            .flatMap(\.items)
            .filter { $0.kind == .note && $0.id != "source" }
            .sorted {
                if $0.measureNumber != $1.measureNumber { return $0.measureNumber < $1.measureNumber }
                return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
            }

        XCTAssertEqual(inserted.map(\.measureNumber), [1, 2])
        XCTAssertEqual(inserted.map(\.displayDuration.denominator), [32, 16])
        XCTAssertEqual(inserted.map(\.durationInQuarterNotes), [0.125, 0.25])
        XCTAssertEqual(inserted.first?.tieTargetItemID, inserted.last?.id)
    }

    func testPlannerFailsAtomicallyWhenNextItemIsNote() {
        let pitch = NotationPitch(step: .g, octave: 4)
        let measures = scoreMeasures(
            duration: 4,
            notationItems: [
                note(id: "source", pitch: pitch, measure: 1, start: 0, offset: 0, duration: 1),
                note(id: "blocker", pitch: pitch, measure: 1, start: 0, offset: 1, duration: 1)
            ]
        )

        XCTAssertNil(NotationNoteInsertionPlanner.plan(
            in: measures,
            sourceItemID: "source",
            selectedDuration: NotationDuration(denominator: 4)
        ))
    }

    func testInsertionPlannerUsesThreeFourMeasureBoundary() throws {
        let pitch = NotationPitch(step: .b, octave: 4)
        let measures = scoreMeasures(
            duration: 3,
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            notationItems: [
                note(id: "existing", pitch: pitch, measure: 1, start: 0, offset: 0, duration: 2),
                rest(id: "tail", measure: 1, start: 0, offset: 2, duration: 1)
            ]
        )
        let firstMeasure = try XCTUnwrap(measures.first { $0.number == 1 })
        let plan = try XCTUnwrap(NotationNoteInsertionPlanner.planInsertion(
            in: measures,
            placement: NotationNotePlacement(
                measure: firstMeasure,
                offsetInQuarterNotes: 2,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2),
                pitch: pitch,
                x: 0,
                y: 0
            )
        ))
        let inserted = plan.replacements
            .flatMap(\.items)
            .filter { $0.kind == .note && $0.id != "existing" }
            .sorted {
                if $0.measureNumber != $1.measureNumber { return $0.measureNumber < $1.measureNumber }
                return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
            }

        XCTAssertEqual(inserted.map(\.measureNumber), [1, 2])
        XCTAssertEqual(inserted.map(\.offsetInQuarterNotes), [2, 0])
        XCTAssertEqual(inserted.map(\.durationInQuarterNotes), [1, 1])
        XCTAssertEqual(inserted[0].tieTargetItemID, inserted[1].id)
    }

    func testResolverAcceptsCrossMeasureConnectionAndRejectsPitchMismatch() throws {
        let pitch = NotationPitch(step: .a, octave: 4)
        let source = note(
            id: "source",
            pitch: pitch,
            measure: 1,
            start: 0,
            offset: 3,
            duration: 1,
            tieTargetItemID: "target"
        )
        let target = note(id: "target", pitch: pitch, measure: 2, start: 2, offset: 0, duration: 1)
        let measures = scoreMeasures(duration: 8, notationItems: [source, target])

        XCTAssertEqual(NotationTieResolver.connections(in: measures).map(\.id), ["source->target"])

        var mismatchedTarget = target
        mismatchedTarget.pitch = NotationPitch(step: .b, octave: 4)
        let mismatchedMeasures = scoreMeasures(duration: 8, notationItems: [source, mismatchedTarget])
        XCTAssertTrue(NotationTieResolver.connections(in: mismatchedMeasures).isEmpty)
    }

    func testOldNotationItemJSONDecodesWithoutTie() throws {
        let json = """
        {
          "id":"legacy",
          "kind":"note",
          "pitch":{"step":"C","octave":4,"alter":0},
          "measureNumber":1,
          "measureStartTime":0,
          "offsetInQuarterNotes":0,
          "durationInQuarterNotes":1,
          "displayDuration":{"denominator":4}
        }
        """
        let item = try JSONDecoder().decode(NotationMeasureItem.self, from: Data(json.utf8))
        XCTAssertNil(item.tieTargetItemID)
    }

    func testNotationItemTieRoundTripsThroughJSON() throws {
        let item = note(
            id: "source",
            pitch: NotationPitch(step: .c, octave: 4),
            measure: 1,
            start: 0,
            offset: 0,
            duration: 1,
            tieTargetItemID: "target"
        )

        let decoded = try JSONDecoder().decode(
            NotationMeasureItem.self,
            from: JSONEncoder().encode(item)
        )
        XCTAssertEqual(decoded.tieTargetItemID, "target")
    }

    func testNormalizerClearsTieToTargetRemovedAsInvalid() throws {
        let pitch = NotationPitch(step: .c, octave: 4)
        let source = note(
            id: "source",
            pitch: pitch,
            measure: 1,
            start: 0,
            offset: 0,
            duration: 1,
            tieTargetItemID: "target"
        )
        let invalidTarget = note(
            id: "target",
            pitch: pitch,
            measure: 1,
            start: 0,
            offset: 1,
            duration: 0
        )

        let normalized = ProjectStateNormalizer.normalizedNotationItems(
            [source, invalidTarget],
            duration: 4,
            notationPartClefs: [:]
        )

        XCTAssertEqual(normalized.map(\.id), ["source"])
        XCTAssertNil(try XCTUnwrap(normalized.first).tieTargetItemID)
    }

    private func scoreMeasures(
        duration: TimeInterval,
        timeSignature: TimeSignature = .fourFour,
        notationItems: [NotationMeasureItem]
    ) -> [ScoreMeasure] {
        NotationViewportFactory().scoreState(
            tempoMap: tempoMap(duration: duration, timeSignature: timeSignature),
            duration: duration,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: nil,
            notationItems: notationItems
        ).measures
    }

    private func tempoMap(
        duration: TimeInterval,
        timeSignature: TimeSignature = .fourFour
    ) -> TempoMap {
        TempoMap(
            baseSettings: BeatGridSettings(bpm: 120, timeSignature: timeSignature),
            markers: [],
            duration: duration
        )
    }

    private func note(
        id: String,
        pitch: NotationPitch,
        measure: Int,
        start: TimeInterval,
        offset: Double,
        duration: Double,
        tieTargetItemID: String? = nil
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: pitch,
            measureNumber: measure,
            measureStartTime: start,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: duration,
            displayDuration: displayDuration(for: duration),
            tieTargetItemID: tieTargetItemID
        )
    }

    private func rest(
        id: String,
        measure: Int,
        start: TimeInterval,
        offset: Double,
        duration: Double,
        denominator: Int = 4
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            measureNumber: measure,
            measureStartTime: start,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: duration,
            displayDuration: NotationDuration(denominator: denominator)
        )
    }

    private func displayDuration(for duration: Double) -> NotationDuration {
        [1, 2, 4, 8, 16, 32]
            .map { NotationDuration(denominator: $0) }
            .first { abs($0.durationInQuarterNotes - duration) < 0.0001 }
            ?? NotationDuration(denominator: 4)
    }
}

final class ViewModelNotationTieTests: XCTestCase {
    @MainActor
    func testTieCommandExtendsSelectionWithoutAuditionAndUsesSingleUndoStep() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .d, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
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
                durationInQuarterNotes: 3,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let source = try XCTUnwrap(measure.notationItems.first { $0.id == "source" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: source))

        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertEqual(viewModel.tieCommandStatus, .ready)
        XCTAssertTrue(viewModel.isTieCommandInScope)
        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())
        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertTrue(auditioner.auditionedPitches.isEmpty)

        let tiedMeasure = try notationMeasure(1, in: viewModel)
        let tiedNotes = tiedMeasure.notationItems.filter { $0.kind == .note }
        XCTAssertEqual(tiedNotes.count, 2)
        XCTAssertEqual(tiedNotes[0].tieTargetItemID, tiedNotes[1].id)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, tiedNotes[1].id)
        XCTAssertEqual(viewModel.selectedNotationItem?.measureNumber, tiedNotes[1].measureNumber)
        XCTAssertEqual(viewModel.selectedNotationItem?.measureStartTime, tiedNotes[1].measureStartTime)
        XCTAssertEqual(viewModel.selectedNotationItem?.partID, tiedNotes[1].partID)
        XCTAssertTrue(undoManager.canUndo)

        viewModel.undoLastEdit()
        XCTAssertEqual(try notationMeasure(1, in: viewModel).notationItems.filter { $0.kind == .note }.count, 1)
        XCTAssertFalse(undoManager.canUndo)

        viewModel.redoLastEdit()
        XCTAssertEqual(try notationMeasure(1, in: viewModel).notationItems.filter { $0.kind == .note }.count, 2)
        XCTAssertFalse(undoManager.canRedo)
    }

    @MainActor
    func testRepeatedTieCommandExtendsFromFinalGeneratedNote() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let pitch = NotationPitch(step: .f, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let source = try XCTUnwrap(measure.notationItems.first { $0.id == "source" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: source))

        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())
        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())

        let notes = try notationMeasure(1, in: viewModel).notationItems.filter { $0.kind == .note }
        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes[0].tieTargetItemID, notes[1].id)
        XCTAssertEqual(notes[1].tieTargetItemID, notes[2].id)
        XCTAssertNil(notes[2].tieTargetItemID)
    }

    @MainActor
    func testTieCommandSpansMeasuresAndUndoRestoresExactNotationState() throws {
        let viewModel = try loadedNotationViewModel(duration: 10)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .g, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
        let originalItems = viewModel.notationItems
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let source = try XCTUnwrap(firstMeasure.notationItems.first { $0.id == "source" })
        viewModel.selectNotationItem(NotationItemSelection(measure: firstMeasure, item: source))

        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())

        let tiedItems = viewModel.notationItems
        let tiedNotes = tiedItems.filter { $0.kind == .note }.sorted {
            if $0.measureNumber != $1.measureNumber { return $0.measureNumber < $1.measureNumber }
            return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
        }
        XCTAssertEqual(tiedNotes.map(\.measureNumber), [1, 1, 2])
        XCTAssertEqual(tiedNotes.map(\.durationInQuarterNotes), [2, 1, 1])
        XCTAssertEqual(tiedNotes[0].tieTargetItemID, tiedNotes[1].id)
        XCTAssertEqual(tiedNotes[1].tieTargetItemID, tiedNotes[2].id)
        XCTAssertNil(tiedNotes[2].tieTargetItemID)
        XCTAssertEqual(viewModel.selectedNotationItem?.measureNumber, 2)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, tiedNotes[2].id)

        viewModel.undoLastEdit()
        XCTAssertEqual(viewModel.notationItems, originalItems)

        viewModel.redoLastEdit()
        XCTAssertEqual(viewModel.notationItems, tiedItems)
    }

    @MainActor
    func testTieCommandIsAvailableInNoteEntryModeWithoutSelectionAndNoOpsCleanly() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.setNotationNoteEntryModeEnabled(true)
        viewModel.markProjectClean()
        undoManager.removeAllActions()
        let originalItems = viewModel.notationItems

        XCTAssertEqual(viewModel.tieCommandStatus, .blocked(.selectNote))
        XCTAssertTrue(viewModel.isTieCommandInScope)
        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())

        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertTrue(viewModel.isNotationNoteEntryModeEnabled)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
    }

    @MainActor
    func testSelectedNoteTieCanOverlapAnotherPitch() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
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
        undoManager.removeAllActions()
        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertEqual(viewModel.tieCommandStatus, .ready)
        XCTAssertTrue(viewModel.isTieCommandInScope)
        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())

        XCTAssertEqual(viewModel.notationItems.filter { $0.kind == .note }.count, 3)
        XCTAssertNotNil(viewModel.notationItems.first { $0.id == "source" }?.tieTargetItemID)
        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
    }

    @MainActor
    func testSelectedNoteWithOutgoingTieRemainsInCommandScopeAndNoOpsCleanly() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .c, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4),
                tieTargetItemID: "target"
            ),
            NotationMeasureItem(
                id: "target",
                kind: .note,
                pitch: pitch,
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
        undoManager.removeAllActions()
        let originalItems = viewModel.notationItems
        let originalSelection = viewModel.selectedNotationItem

        XCTAssertEqual(viewModel.tieCommandStatus, .blocked(.alreadyTied))
        XCTAssertTrue(viewModel.isTieCommandInScope)
        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())

        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertEqual(viewModel.selectedNotationItem, originalSelection)
        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
    }

    @MainActor
    func testSelectedRestTieNoOpsWithoutChangingSelectionOrMode() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "selected-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let rest = try XCTUnwrap(measure.notationItems.first { $0.id == "selected-rest" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: rest))
        viewModel.markProjectClean()
        undoManager.removeAllActions()
        let originalSelection = viewModel.selectedNotationItem

        XCTAssertEqual(viewModel.tieCommandStatus, .unavailable)
        XCTAssertFalse(viewModel.isTieCommandInScope)
        XCTAssertFalse(viewModel.handleAddTiedNotationNoteCommand())

        XCTAssertEqual(viewModel.selectedNotationItem, originalSelection)
        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
    }

    @MainActor
    func testStaleSelectedNoteTieDoesNotContinueReplacementAtSameOffset() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .d, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "selected-source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let selectedMeasure = try notationMeasure(1, in: viewModel)
        let selectedSource = try XCTUnwrap(selectedMeasure.notationItems.first { $0.id == "selected-source" })
        viewModel.selectNotationItem(NotationItemSelection(measure: selectedMeasure, item: selectedSource))
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "replacement-source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        undoManager.removeAllActions()
        let originalItems = viewModel.notationItems
        let staleSelection = viewModel.selectedNotationItem

        XCTAssertEqual(viewModel.tieCommandStatus, .unavailable)
        XCTAssertFalse(viewModel.isTieCommandInScope)
        XCTAssertFalse(viewModel.handleAddTiedNotationNoteCommand())

        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertEqual(viewModel.selectedNotationItem, staleSelection)
        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
    }

    @MainActor
    func testSelectedNoteTieAtAudioEndNoOpsWithoutUsingPartialMeasureTail() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 1,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source-at-audio-end",
                kind: .note,
                pitch: NotationPitch(step: .g, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let source = try XCTUnwrap(measure.notationItems.first { $0.id == "source-at-audio-end" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: source))
        viewModel.markProjectClean()
        undoManager.removeAllActions()
        let originalItems = viewModel.notationItems
        let originalSelection = viewModel.selectedNotationItem

        XCTAssertEqual(viewModel.tieCommandStatus, .blocked(.audioBoundary))
        XCTAssertTrue(viewModel.isTieCommandInScope)
        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())

        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertEqual(viewModel.selectedNotationItem, originalSelection)
        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(auditioner.attemptedPitches.isEmpty)
    }

    @MainActor
    func testCrossMeasureNoteInsertionSplitsAtBarlineAndUsesSingleUndoStep() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .e, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "existing-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 3,
                displayDuration: NotationDuration(denominator: 2, isDotted: true)
            ),
            NotationMeasureItem(
                id: "trailing-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        undoManager.removeAllActions()
        let originalItems = viewModel.notationItems
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let placement = NotationNotePlacement(
            measure: firstMeasure,
            offsetInQuarterNotes: 3,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2),
            pitch: pitch,
            x: 0,
            y: 0
        )

        XCTAssertTrue(viewModel.insertNotationNote(placement))

        let insertedItems = viewModel.notationItems
        let insertedNotes = insertedItems
            .filter { $0.kind == .note && $0.id != "existing-note" }
            .sorted {
                if $0.measureNumber != $1.measureNumber { return $0.measureNumber < $1.measureNumber }
                return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
            }
        XCTAssertEqual(insertedNotes.map(\.measureNumber), [1, 2])
        XCTAssertEqual(insertedNotes.map(\.offsetInQuarterNotes), [3, 0])
        XCTAssertEqual(insertedNotes.map(\.durationInQuarterNotes), [1, 1])
        XCTAssertEqual(insertedNotes.map(\.pitch), [pitch, pitch])
        XCTAssertEqual(insertedNotes[0].tieTargetItemID, insertedNotes[1].id)
        XCTAssertNil(insertedNotes[1].tieTargetItemID)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, insertedNotes[0].id)
        XCTAssertEqual(auditioner.auditionedPitches, [pitch])

        viewModel.undoLastEdit()
        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertFalse(undoManager.canUndo)

        viewModel.redoLastEdit()
        XCTAssertEqual(viewModel.notationItems, insertedItems)
    }

    @MainActor
    func testCrossMeasureStemInsertionDoesNotChangeMainPart() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let bassPart = NotationPartID.stem(.bass)
        let mainItems = [
            NotationMeasureItem(
                id: "main-first",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "main-second",
                kind: .note,
                pitch: NotationPitch(step: .d, octave: 4),
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.notationItems = mainItems + [
            NotationMeasureItem(
                id: "bass-existing",
                partID: bassPart,
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 3,
                displayDuration: NotationDuration(denominator: 2, isDotted: true)
            ),
            NotationMeasureItem(
                id: "bass-tail",
                partID: bassPart,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let bassMeasure = try notationMeasure(1, in: viewModel, partID: bassPart)
        let pitch = NotationPitch(step: .e, octave: 2)
        let placement = NotationNotePlacement(
            measure: bassMeasure,
            partID: bassPart,
            offsetInQuarterNotes: 3,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2),
            pitch: pitch,
            x: 0,
            y: 0
        )

        XCTAssertTrue(viewModel.insertNotationNote(placement))

        XCTAssertEqual(viewModel.notationItems.filter { $0.partID == .main }, mainItems)
        let insertedBassNotes = viewModel.notationItems
            .filter { $0.partID == bassPart && $0.kind == .note && $0.id != "bass-existing" }
            .sorted {
                if $0.measureNumber != $1.measureNumber { return $0.measureNumber < $1.measureNumber }
                return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
            }
        XCTAssertEqual(insertedBassNotes.map(\.measureNumber), [1, 2])
        XCTAssertEqual(insertedBassNotes.map(\.pitch), [pitch, pitch])
        XCTAssertEqual(insertedBassNotes[0].tieTargetItemID, insertedBassNotes[1].id)
    }

    @MainActor
    func testCrossMeasureNoteInsertionCanOverlapNoteAtNextMeasureStart() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let pitch = NotationPitch(step: .e, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "existing-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 3,
                displayDuration: NotationDuration(denominator: 2, isDotted: true)
            ),
            NotationMeasureItem(
                id: "trailing-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "blocker",
                kind: .note,
                pitch: NotationPitch(step: .g, octave: 4),
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        let placement = NotationNotePlacement(
            measure: try notationMeasure(1, in: viewModel),
            offsetInQuarterNotes: 3,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2),
            pitch: pitch,
            x: 0,
            y: 0
        )

        XCTAssertTrue(viewModel.insertNotationNote(placement))
        XCTAssertEqual(viewModel.notationItems.filter { $0.kind == .note }.count, 4)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertEqual(auditioner.attemptedPitches, [pitch])
    }

    @MainActor
    func testCrossMeasureNoteInsertionFailsAtProjectEnd() throws {
        let viewModel = try loadedNotationViewModel(duration: 2)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "existing-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 3,
                displayDuration: NotationDuration(denominator: 2, isDotted: true)
            ),
            NotationMeasureItem(
                id: "trailing-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        let originalItems = viewModel.notationItems
        let placement = NotationNotePlacement(
            measure: try notationMeasure(1, in: viewModel),
            offsetInQuarterNotes: 3,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2),
            pitch: NotationPitch(step: .e, octave: 4),
            x: 0,
            y: 0
        )

        XCTAssertFalse(viewModel.insertNotationNote(placement))
        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testOverflowingRestPlacementRemainsMeasureLocalAndFailsWithoutMutation() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "existing-note",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 3,
                displayDuration: NotationDuration(denominator: 2, isDotted: true)
            ),
            NotationMeasureItem(
                id: "trailing-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let selectedNote = try XCTUnwrap(measure.notationItems.first { $0.id == "existing-note" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: selectedNote))
        viewModel.markProjectClean()
        undoManager.removeAllActions()
        let originalItems = viewModel.notationItems
        let originalSelection = viewModel.selectedNotationItem
        let placement = NotationRestPlacement(
            measure: measure,
            offsetInQuarterNotes: 3,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2),
            x: 0
        )

        XCTAssertFalse(viewModel.insertNotationRest(placement))
        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertEqual(viewModel.selectedNotationItem, originalSelection)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testSelectedStemTieUsesSourceDurationAcrossThreeFourBoundary() throws {
        let viewModel = try loadedNotationViewModel(duration: 6)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)
        let bassPart = NotationPartID.stem(.bass)
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
        let source = NotationMeasureItem(
            id: "bass-source",
            partID: bassPart,
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 2),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        viewModel.notationItems = [mainNote, source]
        viewModel.setNotationNoteEntryModeEnabled(true)
        viewModel.setNotationDurationDenominator(16)
        let bassMeasure = try notationMeasure(1, in: viewModel, partID: bassPart)
        let selectedSource = try XCTUnwrap(bassMeasure.notationItems.first { $0.id == source.id })
        viewModel.selectNotationItem(NotationItemSelection(
            measure: bassMeasure,
            item: selectedSource,
            partID: bassPart
        ))
        viewModel.markProjectClean()
        undoManager.removeAllActions()
        let originalItems = viewModel.notationItems

        XCTAssertNil(viewModel.notationEntryMode)
        XCTAssertEqual(viewModel.tieCommandStatus, .ready)
        XCTAssertTrue(viewModel.handleAddTiedNotationNoteCommand())
        XCTAssertNil(viewModel.notationEntryMode)

        let tiedItems = viewModel.notationItems
        XCTAssertEqual(tiedItems.filter { $0.partID == .main }, [mainNote])
        let bassNotes = tiedItems
            .filter { $0.partID == bassPart && $0.kind == .note }
            .sorted {
                if $0.measureNumber != $1.measureNumber { return $0.measureNumber < $1.measureNumber }
                return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
            }
        XCTAssertEqual(bassNotes.map(\.measureNumber), [1, 1, 2])
        XCTAssertEqual(bassNotes.map(\.durationInQuarterNotes), [2, 1, 1])
        XCTAssertEqual(bassNotes.map(\.displayDuration.denominator), [2, 4, 4])
        XCTAssertEqual(bassNotes[0].tieTargetItemID, bassNotes[1].id)
        XCTAssertEqual(bassNotes[1].tieTargetItemID, bassNotes[2].id)
        XCTAssertEqual(viewModel.selectedNotationItem?.partID, bassPart)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, bassNotes[2].id)

        viewModel.undoLastEdit()
        XCTAssertEqual(viewModel.notationItems, originalItems)

        viewModel.redoLastEdit()
        XCTAssertEqual(viewModel.notationItems, tiedItems)
    }

    @MainActor
    func testTempoTimeSignatureMarkerInvalidatesTieAndUndoRestoresIt() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .c, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4),
                tieTargetItemID: "target"
            ),
            NotationMeasureItem(
                id: "target",
                kind: .note,
                pitch: pitch,
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        undoManager.removeAllActions()

        viewModel.addTempoTimeSignatureMarker(
            at: 1,
            bpm: 120,
            beatsPerBar: 3
        )

        XCTAssertNil(viewModel.notationItems.first { $0.id == "source" }?.tieTargetItemID)

        viewModel.undoLastEdit()
        XCTAssertEqual(
            viewModel.notationItems.first { $0.id == "source" }?.tieTargetItemID,
            "target"
        )
    }

    @MainActor
    func testProjectSaveAndOpenPreservesValidCrossMeasureTie() async throws {
        let audioURL = try temporaryAudioFile(duration: 8)
        let directory = temporaryDirectory()
        let projectURL = directory.appendingPathComponent("notation-tie.jammlab")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: directory)
        }

        let projectService = ProjectDocumentService()
        let makeViewModel: () throws -> AudioPlayerViewModel = {
            AudioPlayerViewModel(
                analyzer: MockAnalyzer(),
                peakformProvider: MockPeakformProvider(),
                playbackEngine: MockPlaybackEngine(),
                projectService: projectService,
                recentProjectsStore: RecentProjectsStore(defaults: try self.temporaryUserDefaults()),
                isSandboxed: { false }
            )
        }
        let bassPart = NotationPartID.stem(.bass)
        let pitch = NotationPitch(step: .a, octave: 2)
        let source = NotationMeasureItem(
            id: "source",
            partID: bassPart,
            kind: .note,
            pitch: pitch,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 3,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            tieTargetItemID: "target"
        )
        let target = NotationMeasureItem(
            id: "target",
            partID: bassPart,
            kind: .note,
            pitch: pitch,
            measureNumber: 2,
            measureStartTime: 2,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let savingViewModel = try makeViewModel()
        try savingViewModel.loadImportedAudio(
            ImportedAudioFile(url: audioURL, displayName: "notation.wav", duration: 8)
        )
        savingViewModel.beatGridSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        savingViewModel.tempoBPM = 120
        savingViewModel.applyTempoMapToPlaybackEngine()
        savingViewModel.notationItems = [source, target]

        let didSave = await savingViewModel.saveProject(to: projectURL)
        XCTAssertTrue(didSave)
        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(savedProject.notationItems, [source, target])

        let restoredViewModel = try makeViewModel()
        await restoredViewModel.openProject(at: projectURL)

        XCTAssertEqual(restoredViewModel.notationItems, [source, target])
        let restoredMeasures = [
            try notationMeasure(1, in: restoredViewModel, partID: bassPart),
            try notationMeasure(2, in: restoredViewModel, partID: bassPart)
        ]
        XCTAssertEqual(
            NotationTieResolver.connections(in: restoredMeasures).map(\.id),
            ["source->target"]
        )
        XCTAssertFalse(restoredViewModel.isProjectModified)
    }

    @MainActor
    func testTimeSignatureChangeClearsInvalidCrossMeasureTieAndUndoRestoresIt() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .c, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4),
                tieTargetItemID: "target"
            ),
            NotationMeasureItem(
                id: "target",
                kind: .note,
                pitch: pitch,
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]

        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)
        XCTAssertNil(viewModel.notationItems.first { $0.id == "source" }?.tieTargetItemID)

        viewModel.undoLastEdit()
        XCTAssertEqual(
            viewModel.notationItems.first { $0.id == "source" }?.tieTargetItemID,
            "target"
        )
    }

    @MainActor
    func testTargetPitchEditClearsInvalidIncomingTieRelationship() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let pitch = NotationPitch(step: .c, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4),
                tieTargetItemID: "target"
            ),
            NotationMeasureItem(
                id: "target",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = try notationMeasure(1, in: viewModel)
        let target = try XCTUnwrap(measure.notationItems.first { $0.id == "target" })
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: target))

        XCTAssertTrue(viewModel.changeSelectedNotationNotePitch(
            to: NotationPitch(step: .d, octave: 4),
            shouldAudition: false
        ))
        XCTAssertNil(viewModel.notationItems.first { $0.id == "source" }?.tieTargetItemID)
    }

    @MainActor
    func testSourceDurationEditClearsNoncontiguousOutgoingTie() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let pitch = NotationPitch(step: .c, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4),
                tieTargetItemID: "target"
            ),
            NotationMeasureItem(
                id: "target",
                kind: .note,
                pitch: pitch,
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

        viewModel.setNotationDurationDenominator(8)

        XCTAssertNil(viewModel.notationItems.first { $0.id == "source" }?.tieTargetItemID)
    }

    @MainActor
    func testMeasureClipboardRemapsOnlyInternalTieTargets() throws {
        let viewModel = try loadedNotationViewModel(duration: 16)
        let pitch = NotationPitch(step: .a, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 3,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4),
                tieTargetItemID: "target"
            ),
            NotationMeasureItem(
                id: "target",
                kind: .note,
                pitch: pitch,
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let first = try notationMeasure(1, in: viewModel)
        let second = try notationMeasure(2, in: viewModel)
        viewModel.selectNotationMeasure(first)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        XCTAssertNil(viewModel.notationMeasureClipboard?.measures.first?.notationItems.first {
            $0.sourceItemID == "source"
        }?.tieTargetItemID)

        viewModel.selectNotationMeasure(first)
        viewModel.selectNotationMeasure(second, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        let third = try notationMeasure(3, in: viewModel)
        viewModel.selectNotationMeasure(third)
        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let pastedSource = try XCTUnwrap(try notationMeasure(3, in: viewModel).notationItems.first {
            $0.kind == .note
        })
        let pastedTarget = try XCTUnwrap(try notationMeasure(4, in: viewModel).notationItems.first {
            $0.kind == .note
        })
        XCTAssertNotEqual(pastedSource.id, "source")
        XCTAssertNotEqual(pastedTarget.id, "target")
        XCTAssertEqual(pastedSource.tieTargetItemID, pastedTarget.id)
    }

    @MainActor
    func testPastingSemanticallyIdenticalTieChainIsNoOpDespiteDifferentIDs() throws {
        let viewModel = try loadedNotationViewModel(duration: 16)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let pitch = NotationPitch(step: .a, octave: 4)
        viewModel.notationItems = [
            tiedNote(id: "source-1", targetID: "target-1", pitch: pitch, measure: 1, start: 0, offset: 3),
            tiedNote(id: "target-1", targetID: nil, pitch: pitch, measure: 2, start: 2, offset: 0),
            tiedNote(id: "source-2", targetID: "target-2", pitch: pitch, measure: 3, start: 4, offset: 3),
            tiedNote(id: "target-2", targetID: nil, pitch: pitch, measure: 4, start: 6, offset: 0)
        ]
        let originalItems = viewModel.notationItems
        let first = try notationMeasure(1, in: viewModel)
        let second = try notationMeasure(2, in: viewModel)
        viewModel.selectNotationMeasure(first)
        viewModel.selectNotationMeasure(second, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(try notationMeasure(3, in: viewModel))
        viewModel.markProjectClean()
        undoManager.removeAllActions()

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())
        XCTAssertEqual(viewModel.notationItems, originalItems)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(undoManager.canUndo)
    }

    private func tiedNote(
        id: String,
        targetID: String?,
        pitch: NotationPitch,
        measure: Int,
        start: TimeInterval,
        offset: Double
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: pitch,
            measureNumber: measure,
            measureStartTime: start,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            tieTargetItemID: targetID
        )
    }
}

final class NotationTieLayoutAndExportTests: XCTestCase {
    func testSystemProjectionProvidesPartialTieAtBothBoundaries() throws {
        let pitch = NotationPitch(step: .c, octave: 4)
        let state = NotationViewportFactory().scoreState(
            tempoMap: TempoMap(
                baseSettings: BeatGridSettings(bpm: 120, timeSignature: .fourFour),
                markers: [],
                duration: 8
            ),
            duration: 8,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: nil,
            notationItems: [
                NotationMeasureItem(
                    id: "source",
                    kind: .note,
                    pitch: pitch,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 3,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4),
                    tieTargetItemID: "target"
                ),
                NotationMeasureItem(
                    id: "target",
                    kind: .note,
                    pitch: pitch,
                    measureNumber: 2,
                    measureStartTime: 2,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )
        let systems = state.systems(measuresPerSystem: 1)
        XCTAssertEqual(systems.prefix(2).map { $0.viewportState.tieConnections.count }, [1, 1])
        let content = NotationScoreContent(
            availability: .ready,
            keySignature: state.keySignature,
            measures: state.measures
        )
        let factory = NotationViewportFactory()
        let sourceViewport = factory.viewportState(
            content: content,
            duration: 8,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            visibleMeasureCount: 1
        )
        let targetViewport = factory.viewportState(
            content: content,
            duration: 8,
            currentTime: 0,
            playbackMarkerTime: 2.1,
            isPlaying: false,
            visibleMeasureCount: 1
        )
        XCTAssertEqual(sourceViewport.tieConnections.count, 1)
        XCTAssertEqual(targetViewport.tieConnections.count, 1)

        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 10,
            staffEndX: 190
        )
        let outgoing = try XCTUnwrap(NotationTrackLayoutItems.ties(
            visibleMeasures: systems[0].viewportState.visibleMeasures,
            geometries: [geometry],
            connections: systems[0].viewportState.tieConnections,
            staffTop: 40
        ).first)
        let incoming = try XCTUnwrap(NotationTrackLayoutItems.ties(
            visibleMeasures: systems[1].viewportState.visibleMeasures,
            geometries: [geometry],
            connections: systems[1].viewportState.tieConnections,
            staffTop: 40
        ).first)
        XCTAssertEqual(outgoing.end.x, geometry.staffEndX, accuracy: 0.0001)
        XCTAssertEqual(incoming.start.x, geometry.staffStartX, accuracy: 0.0001)
        XCTAssertEqual(outgoing.placement, .below)
    }

    func testMusicXMLExportsTieAndTiedRolesInSchemaOrder() throws {
        let pitch = NotationPitch(step: .e, octave: 4)
        let state = NotationViewportFactory().scoreState(
            tempoMap: TempoMap(
                baseSettings: BeatGridSettings(bpm: 120, timeSignature: .fourFour),
                markers: [],
                duration: 4
            ),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: nil,
            notationItems: [
                NotationMeasureItem(
                    id: "source",
                    kind: .note,
                    pitch: pitch,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4),
                    tieTargetItemID: "middle"
                ),
                NotationMeasureItem(
                    id: "middle",
                    kind: .note,
                    pitch: pitch,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4),
                    tieTargetItemID: "target"
                ),
                NotationMeasureItem(
                    id: "target",
                    kind: .note,
                    pitch: pitch,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 2,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )
        let data = try MusicXMLNotationExportRenderer(appVersionProvider: { nil }).render(
            NotationExportRequest(displayName: "Tie", score: state, tempoBPM: 120)
        )
        let document = try XMLDocument(data: data)
        let notes = try XCTUnwrap(document.rootElement())
            .elements(forName: "part").flatMap { $0.elements(forName: "measure") }
            .flatMap { $0.elements(forName: "note") }
            .filter { !$0.elements(forName: "pitch").isEmpty }
        let sourceChildren = childElements(in: try XCTUnwrap(notes.first))
        let middleChildren = childElements(in: try XCTUnwrap(notes.dropFirst().first))
        let targetChildren = childElements(in: try XCTUnwrap(notes.dropFirst(2).first))

        XCTAssertEqual(sourceChildren.compactMap(\.name), ["pitch", "duration", "tie", "voice", "type", "notations"])
        XCTAssertEqual(sourceChildren.first { $0.name == "tie" }?.attribute(forName: "type")?.stringValue, "start")
        XCTAssertEqual(sourceChildren.first { $0.name == "notations" }?.elements(forName: "tied").first?.attribute(forName: "type")?.stringValue, "start")
        XCTAssertEqual(
            middleChildren.compactMap(\.name),
            ["pitch", "duration", "tie", "tie", "voice", "type", "notations"]
        )
        XCTAssertEqual(
            middleChildren.filter { $0.name == "tie" }.compactMap {
                $0.attribute(forName: "type")?.stringValue
            },
            ["stop", "start"]
        )
        XCTAssertEqual(
            middleChildren.first { $0.name == "notations" }?.elements(forName: "tied").compactMap {
                $0.attribute(forName: "type")?.stringValue
            },
            ["stop", "start"]
        )
        XCTAssertEqual(targetChildren.first { $0.name == "tie" }?.attribute(forName: "type")?.stringValue, "stop")
        XCTAssertEqual(targetChildren.first { $0.name == "notations" }?.elements(forName: "tied").first?.attribute(forName: "type")?.stringValue, "stop")
    }

    func testTieResolverFindsTargetByIDThroughInterleavedChordMembers() throws {
        let sourcePitch = NotationPitch(step: .c, octave: 4)
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [
                NotationMeasureItem(
                    id: "source",
                    kind: .note,
                    pitch: sourcePitch,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4),
                    tieTargetItemID: "target"
                ),
                NotationMeasureItem(
                    id: "a-interleaved",
                    kind: .note,
                    pitch: NotationPitch(step: .e, octave: 4),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                ),
                NotationMeasureItem(
                    id: "target",
                    kind: .note,
                    pitch: sourcePitch,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )

        let connection = try XCTUnwrap(NotationTieResolver.connections(in: [measure]).first)
        XCTAssertEqual(connection.source.item.id, "source")
        XCTAssertEqual(connection.target.item.id, "target")
    }

    private func childElements(in element: XMLElement) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }
    }
}
