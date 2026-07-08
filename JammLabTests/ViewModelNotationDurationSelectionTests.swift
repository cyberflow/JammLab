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
}
