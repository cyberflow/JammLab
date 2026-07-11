import XCTest
@testable import JammLab

final class ViewModelNotationPasteTests: XCTestCase {
    @MainActor
    func testPasteNotationMeasureReplacesTargetAndSupportsUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let targetMeasure = try notationMeasure(2, in: viewModel)
        let sourceA = HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C")
        let sourceB = HarmonySymbol(time: 1, measureNumber: 1, offsetInQuarterNotes: 2, rawText: "F")
        let targetExisting = HarmonySymbol(time: 2.5, measureNumber: 2, offsetInQuarterNotes: 1, rawText: "G7")
        viewModel.harmonySymbols = [sourceA, sourceB, targetExisting]
        viewModel.markProjectClean()

        viewModel.selectNotationMeasure(sourceMeasure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)
        let beforePaste = viewModel.harmonySymbols
        viewModel.markProjectClean()

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let targetSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        XCTAssertEqual(targetSymbols.map(\.rawText), ["C", "F"])
        XCTAssertEqual(targetSymbols.map(\.id).contains(sourceA.id), false)
        XCTAssertEqual(targetSymbols.map(\.id).contains(sourceB.id), false)
        XCTAssertEqual(targetSymbols[0].time, 2, accuracy: 0.0001)
        XCTAssertEqual(targetSymbols[1].time, 3, accuracy: 0.0001)
        XCTAssertNil(viewModel.selectedHarmonySymbolID)
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [targetMeasure.number])
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.harmonySymbols, beforePaste)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        let redoneTargetSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        XCTAssertEqual(redoneTargetSymbols.map(\.rawText), ["C", "F"])
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testPastingEmptyNotationMeasureClearsTarget() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let emptyMeasure = try notationMeasure(3, in: viewModel)
        let targetMeasure = try notationMeasure(2, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 2.5, measureNumber: 2, offsetInQuarterNotes: 1, rawText: "G7")
        ]

        viewModel.selectNotationMeasure(emptyMeasure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        XCTAssertFalse(viewModel.harmonySymbols.contains {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        })
    }

    @MainActor
    func testPasteNotationMeasureReplacesTargetNotationItemsAndSupportsUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let targetMeasure = try notationMeasure(2, in: viewModel)
        let pitch = NotationPitch(step: .e, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "source-note",
                kind: .note,
                pitch: pitch,
                measureNumber: sourceMeasure.number,
                measureStartTime: sourceMeasure.startTime,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "source-rest",
                measureNumber: sourceMeasure.number,
                measureStartTime: sourceMeasure.startTime,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            ),
            NotationMeasureItem(
                id: "target-rest",
                measureNumber: targetMeasure.number,
                measureStartTime: targetMeasure.startTime,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 1)
            )
        ]
        viewModel.markProjectClean()

        viewModel.selectNotationMeasure(try notationMeasure(1, in: viewModel))
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(try notationMeasure(2, in: viewModel))
        let beforePaste = viewModel.notationItems
        viewModel.markProjectClean()

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let pastedMeasure = try notationMeasure(2, in: viewModel)
        XCTAssertEqual(pastedMeasure.notationItems.map(\.kind), [.note, .rest, .rest])
        XCTAssertEqual(pastedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 3])
        XCTAssertEqual(pastedMeasure.notationItems.map(\.durationInQuarterNotes), [1, 2, 1])
        XCTAssertEqual(pastedMeasure.notationItems.map(\.displayDuration.denominator), [4, 2, 4])
        XCTAssertEqual(pastedMeasure.notationItems.first?.pitch, pitch)
        XCTAssertEqual(pastedMeasure.notationItems.map(\.measureNumber), [
            targetMeasure.number,
            targetMeasure.number,
            targetMeasure.number
        ])
        XCTAssertEqual(pastedMeasure.notationItems.map(\.measureStartTime), [
            targetMeasure.startTime,
            targetMeasure.startTime,
            targetMeasure.startTime
        ])
        XCTAssertFalse(pastedMeasure.notationItems.map(\.id).contains("source-note"))
        XCTAssertFalse(pastedMeasure.notationItems.map(\.id).contains("source-rest"))
        XCTAssertFalse(pastedMeasure.notationItems.map(\.id).contains("target-rest"))
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.notationItems, beforePaste)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        let redoneMeasure = try notationMeasure(2, in: viewModel)
        XCTAssertEqual(redoneMeasure.notationItems.map(\.kind), [.note, .rest, .rest])
        XCTAssertEqual(redoneMeasure.notationItems.first?.pitch, pitch)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testPasteNotationMeasureSkipsOffsetsOutsideTargetTimeSignature() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 120, beatsPerBar: 3)
        viewModel.markProjectClean()
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let targetMeasure = try notationMeasure(2, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 1.5, measureNumber: 1, offsetInQuarterNotes: 3, rawText: "D")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let targetSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        XCTAssertEqual(targetSymbols.map(\.rawText), ["C"])
        XCTAssertEqual(try XCTUnwrap(targetSymbols.first).time, 2, accuracy: 0.0001)
    }
}
