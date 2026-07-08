import XCTest
@testable import JammLab

final class ViewModelNotationClipboardTests: XCTestCase {
    @MainActor
    func testCopyNotationMeasureCopiesOnlyHarmonies() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        viewModel.notes = [
            TimecodedNote(kind: .region, time: measure.startTime, duration: 1, title: "Intro")
        ]
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0.5, measureNumber: 99, offsetInQuarterNotes: 99, rawText: "F"),
            HarmonySymbol(time: measure.endTime, measureNumber: 1, offsetInQuarterNotes: 4, rawText: "G")
        ]

        viewModel.selectNotationMeasure(measure)

        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        XCTAssertEqual(viewModel.notationMeasureClipboard?.measures.map(\.items), [[
            NotationMeasureClipboardItem(offsetInQuarterNotes: 1, rawText: "F")
        ]])
    }

    @MainActor
    func testCopyNotationMeasureRangePreservesOrderAndEmptyMeasures() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(firstMeasure)
        viewModel.selectNotationMeasure(thirdMeasure, extendingSelection: true)

        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        XCTAssertEqual(viewModel.notationMeasureClipboard?.measures.map(\.items), [
            [NotationMeasureClipboardItem(offsetInQuarterNotes: 0, rawText: "C")],
            [],
            [NotationMeasureClipboardItem(offsetInQuarterNotes: 0, rawText: "Am")]
        ])
    }

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
    func testPasteNotationMeasureRangeStartsAtFirstSelectedTarget() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let secondMeasure = try notationMeasure(2, in: viewModel)
        let targetMeasure = try notationMeasure(3, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 2, measureNumber: 2, offsetInQuarterNotes: 0, rawText: "F"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "G"),
            HarmonySymbol(time: 6, measureNumber: 4, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let thirdMeasureSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        let fourthMeasureSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: fourthMeasure)
        }
        XCTAssertEqual(thirdMeasureSymbols.map(\.rawText), ["C"])
        XCTAssertEqual(fourthMeasureSymbols.map(\.rawText), ["F"])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [3, 4])
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
    func testPastingNotationMeasureRangePreservesEmptyMeasuresByClearingTargets() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let secondMeasure = try notationMeasure(2, in: viewModel)
        let targetMeasure = try notationMeasure(3, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "G"),
            HarmonySymbol(time: 6, measureNumber: 4, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        XCTAssertEqual(viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }.map(\.rawText), ["C"])
        XCTAssertFalse(viewModel.harmonySymbols.contains {
            NotationMeasureTiming.containsEventTime($0.time, in: fourthMeasure)
        })
    }

    @MainActor
    func testPastingNotationMeasureRangeIgnoresOverflowBeyondAvailableTargets() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 2, measureNumber: 2, offsetInQuarterNotes: 0, rawText: "F"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "G"),
            HarmonySymbol(time: 6, measureNumber: 4, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        viewModel.selectNotationMeasure(thirdMeasure, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(fourthMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let fourthMeasureSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: fourthMeasure)
        }
        XCTAssertEqual(fourthMeasureSymbols.map(\.rawText), ["C"])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [4])
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

    @MainActor
    func testCopyRejectsPartialStaleNotationMeasureSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let secondMeasure = try notationMeasure(2, in: viewModel)

        viewModel.selectedNotationMeasures = [
            NotationMeasureSelection(measure: firstMeasure),
            NotationMeasureSelection(
                measure: ScoreMeasure(
                    number: secondMeasure.number,
                    startTime: secondMeasure.startTime,
                    endTime: secondMeasure.endTime + 0.25,
                    attributes: secondMeasure.attributes
                )
            )
        ]

        XCTAssertFalse(viewModel.copySelectedNotationMeasure())
        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
    }

    @MainActor
    func testClearingNotationMeasureSelectionDoesNotClearClipboardOrMarkDirty() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C")
        ]
        viewModel.selectNotationMeasure(measure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.markProjectClean()

        viewModel.clearNotationMeasureSelection()

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertNotNil(viewModel.notationMeasureClipboard)
        XCTAssertFalse(viewModel.isProjectModified)
    }
}
