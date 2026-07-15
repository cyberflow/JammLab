import XCTest
@testable import JammLab

final class NotationDurationEditorTests: XCTestCase {
    func testRecomposesSelectedRestAndRemainingMeasure() throws {
        let measure = makeMeasure()
        let selectedRest = try XCTUnwrap(measure.notationItems.first)

        let items = try XCTUnwrap(NotationDurationEditor.replacementSuffix(
            in: measure,
            selectedItem: selectedRest,
            selectedDuration: NotationDuration(denominator: 4)
        ))

        XCTAssertEqual(items.map(\.displayDuration.denominator), [4, 4, 2])
        XCTAssertEqual(items.map(\.offsetInQuarterNotes), [0, 1, 2])
        XCTAssertEqual(items.map(\.durationInQuarterNotes), [1, 1, 2])
    }

    func testRejectsDurationThatWouldDropTrailingItems() {
        var measure = makeMeasure()
        let note = NotationMeasureItem(
            id: "selected-note",
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 4),
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let trailingRest = NotationMeasureItem(
            id: "trailing-rest",
            kind: .rest,
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        measure.notationItems = [note, trailingRest]

        let items = NotationDurationEditor.replacementSuffix(
            in: measure,
            selectedItem: note,
            selectedDuration: NotationDuration(denominator: 1)
        )

        XCTAssertNil(items)
    }

    private func makeMeasure() -> ScoreMeasure {
        let attributes = MeasureAttributes(
            keySignature: .cMajor,
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            clef: .treble
        )
        let rest = NotationMeasureItem(
            kind: .rest,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1)
        )
        return ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: attributes,
            notationItems: [rest]
        )
    }
}
