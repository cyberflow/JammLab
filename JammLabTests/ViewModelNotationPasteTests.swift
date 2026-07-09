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
