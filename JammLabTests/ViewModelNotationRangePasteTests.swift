import XCTest
@testable import JammLab

final class ViewModelNotationRangePasteTests: XCTestCase {
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
}
