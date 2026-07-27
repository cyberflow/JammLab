import XCTest
@testable import JammLab

final class NotationMeasureTimingTests: XCTestCase {
    func testNotationMeasureTimingUsesHalfOpenMeasureBoundaries() {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble
        )

        XCTAssertTrue(NotationMeasureTiming.containsEventTime(0, in: measure))
        XCTAssertTrue(NotationMeasureTiming.containsEventTime(1.999, in: measure))
        XCTAssertFalse(NotationMeasureTiming.containsEventTime(2, in: measure))
    }

    func testNotationMeasureTimingRecomputesQuarterOffsetsFromMeasureTime() {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 2,
            endTime: 4,
            attributes: .defaultTreble
        )

        XCTAssertEqual(
            NotationMeasureTiming.quarterOffset(for: 3, in: measure),
            2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureTiming.time(forQuarterOffset: 2, in: measure),
            3,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureTimingRecognizesOnlySingleFullMeasureWholeRest() {
        let rest = NotationMeasureItem(
            id: "whole-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1)
        )
        var measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [rest]
        )

        XCTAssertTrue(
            NotationMeasureTiming.isSingleFullMeasureWholeRest(
                measure,
                item: rest
            )
        )
        measure.notationItems.append(
            NotationMeasureItem(
                id: "extra-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 2,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        )
        XCTAssertFalse(
            NotationMeasureTiming.isSingleFullMeasureWholeRest(measure)
        )
    }

    func testVisibleMeasureIndexUsesSuppliedTimeAndHalfOpenInternalBoundaries() {
        let measures = (0..<3).map { index in
            ScoreMeasure(
                number: index + 1,
                startTime: Double(index) * 2,
                endTime: Double(index + 1) * 2,
                attributes: .defaultTreble
            )
        }

        XCTAssertEqual(
            NotationMeasureTiming.visibleMeasureIndex(
                containing: 2,
                in: measures
            ),
            1
        )
        XCTAssertEqual(
            NotationMeasureTiming.visibleMeasureIndex(
                containing: 6,
                in: measures
            ),
            2
        )
        XCTAssertNil(
            NotationMeasureTiming.visibleMeasureIndex(
                containing: -0.1,
                in: measures
            )
        )
    }
}
