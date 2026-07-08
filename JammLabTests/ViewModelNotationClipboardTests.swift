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
