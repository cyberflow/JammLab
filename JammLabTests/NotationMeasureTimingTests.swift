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
}
