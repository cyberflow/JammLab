import XCTest
@testable import JammLab

final class NotationRestLayoutTests: XCTestCase {
    func testNotationMeasureLayoutCentersSingleFullMeasureWholeRest() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let item = NotationMeasureItem(
            id: "whole-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 3,
            displayDuration: NotationDuration(denominator: 1)
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 1.5,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
                clef: .treble
            ),
            notationItems: [item]
        )

        let x = NotationMeasureLayout.notationItemX(
            geometry: geometry,
            measure: measure,
            item: item
        )

        XCTAssertEqual(x, 100, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutDoesNotCenterNonFullMeasureWholeRestCases() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let partialItem = NotationMeasureItem(
            id: "partial",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 1)
        )
        let offsetItem = NotationMeasureItem(
            id: "offset",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1)
        )
        let quarterItem = NotationMeasureItem(
            id: "quarter",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )

        for item in [partialItem, offsetItem, quarterItem] {
            let measure = ScoreMeasure(
                number: 1,
                startTime: 0,
                endTime: 2,
                attributes: .defaultTreble,
                notationItems: [item]
            )
            let expectedX = NotationMeasureLayout.harmonyX(
                geometry: geometry,
                offsetInQuarterNotes: item.offsetInQuarterNotes,
                timeSignature: measure.attributes.timeSignature
            )

            XCTAssertEqual(
                NotationMeasureLayout.notationItemX(
                    geometry: geometry,
                    measure: measure,
                    item: item
                ),
                expectedX,
                accuracy: 0.0001
            )
        }

        let firstSplitItem = NotationMeasureItem(
            id: "split-a",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 1)
        )
        let secondSplitItem = NotationMeasureItem(
            id: "split-b",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        let splitMeasure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [firstSplitItem, secondSplitItem]
        )

        XCTAssertEqual(
            NotationMeasureLayout.notationItemX(
                geometry: geometry,
                measure: splitMeasure,
                item: firstSplitItem
            ),
            NotationMeasureLayout.harmonyX(
                geometry: geometry,
                offsetInQuarterNotes: firstSplitItem.offsetInQuarterNotes,
                timeSignature: splitMeasure.attributes.timeSignature
            ),
            accuracy: 0.0001
        )
    }
}
