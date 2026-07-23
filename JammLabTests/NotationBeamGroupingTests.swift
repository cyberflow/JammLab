import XCTest
@testable import JammLab

final class NotationBeamGroupingTests: XCTestCase {
    func testFourFourGroupsEightEighthNotesByQuarterBeat() {
        XCTAssertEqual(
            groupedIndices(
                timeSignature: .fourFour,
                events: notes(count: 8, denominator: 8)
            ),
            [[0, 1], [2, 3], [4, 5], [6, 7]]
        )
    }

    func testFourFourGroupsSixteenSixteenthNotesByQuarterBeat() {
        XCTAssertEqual(
            groupedIndices(
                timeSignature: .fourFour,
                events: notes(count: 16, denominator: 16)
            ),
            [
                [0, 1, 2, 3],
                [4, 5, 6, 7],
                [8, 9, 10, 11],
                [12, 13, 14, 15]
            ]
        )
    }

    func testFourFourGroupsEighthAndTwoSixteenthsWithinEachBeat() {
        var events: [NotationBeamGroupingEvent] = []
        for beat in 0..<4 {
            let sourceIndex = events.count
            events.append(event(
                sourceIndex: sourceIndex,
                position: Double(beat),
                duration: 0.5,
                levelCount: 1
            ))
            events.append(event(
                sourceIndex: sourceIndex + 1,
                position: Double(beat) + 0.5,
                duration: 0.25,
                levelCount: 2
            ))
            events.append(event(
                sourceIndex: sourceIndex + 2,
                position: Double(beat) + 0.75,
                duration: 0.25,
                levelCount: 2
            ))
        }

        XCTAssertEqual(
            groupedIndices(timeSignature: .fourFour, events: events),
            [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]]
        )
    }

    func testRestEndsOpenGroupAndIsNotIncluded() {
        let events = [
            event(sourceIndex: 0, position: 0, duration: 0.5, levelCount: 1),
            event(
                sourceIndex: 1,
                position: 0.5,
                duration: 0.5,
                levelCount: 0,
                isRest: true
            ),
            event(sourceIndex: 2, position: 1, duration: 0.5, levelCount: 1),
            event(sourceIndex: 3, position: 1.5, duration: 0.5, levelCount: 1)
        ]

        XCTAssertEqual(
            groupedIndices(timeSignature: .fourFour, events: events),
            [[2, 3]]
        )
    }

    func testAdjacentEighthNotesAcrossBeatBoundaryRemainSeparate() {
        let events = [
            event(sourceIndex: 0, position: 0.5, duration: 0.5, levelCount: 1),
            event(sourceIndex: 1, position: 1, duration: 0.5, levelCount: 1)
        ]

        XCTAssertTrue(
            groupedIndices(timeSignature: .fourFour, events: events).isEmpty
        )
    }

    func testNoteWhoseDurationCrossesBeatBoundaryIsNotBeamed() {
        let events = [
            event(sourceIndex: 0, position: 0.5, duration: 0.25, levelCount: 2),
            event(sourceIndex: 1, position: 0.75, duration: 0.5, levelCount: 1)
        ]

        XCTAssertTrue(
            groupedIndices(timeSignature: .fourFour, events: events).isEmpty
        )
    }

    func testNonAdjacentNotesWithinBeatRemainSeparate() {
        let events = [
            event(sourceIndex: 0, position: 0, duration: 0.25, levelCount: 2),
            event(sourceIndex: 1, position: 0.5, duration: 0.25, levelCount: 2)
        ]

        XCTAssertTrue(
            groupedIndices(timeSignature: .fourFour, events: events).isEmpty
        )
    }

    func testThreeFourGroupsSixEighthNotesByQuarterBeat() {
        XCTAssertEqual(
            groupedIndices(
                timeSignature: timeSignature(beats: 3, unit: 4),
                events: notes(count: 6, denominator: 8)
            ),
            [[0, 1], [2, 3], [4, 5]]
        )
    }

    func testThreeFourGroupsTwelveSixteenthNotesByQuarterBeat() {
        XCTAssertEqual(
            groupedIndices(
                timeSignature: timeSignature(beats: 3, unit: 4),
                events: notes(count: 12, denominator: 16)
            ),
            [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11]]
        )
    }

    func testThreeEightGroupsThreeEighthNotesTogether() {
        XCTAssertEqual(
            groupedIndices(
                timeSignature: timeSignature(beats: 3, unit: 8),
                events: notes(count: 3, denominator: 8)
            ),
            [[0, 1, 2]]
        )
    }

    func testSixEightGroupsSixEighthNotesByDottedQuarterBeat() {
        XCTAssertEqual(
            groupedIndices(
                timeSignature: timeSignature(beats: 6, unit: 8),
                events: notes(count: 6, denominator: 8)
            ),
            [[0, 1, 2], [3, 4, 5]]
        )
    }

    func testSixEightGroupsTwelveSixteenthNotesByDottedQuarterBeat() {
        XCTAssertEqual(
            groupedIndices(
                timeSignature: timeSignature(beats: 6, unit: 8),
                events: notes(count: 12, denominator: 16)
            ),
            [[0, 1, 2, 3, 4, 5], [6, 7, 8, 9, 10, 11]]
        )
    }

    func testSixEightRestSeparatesSecondDottedQuarterGroup() {
        var events = notes(count: 3, denominator: 8)
        events.append(event(
            sourceIndex: 3,
            position: 1.5,
            duration: 0.5,
            levelCount: 0,
            isRest: true
        ))
        events.append(event(
            sourceIndex: 4,
            position: 2,
            duration: 0.5,
            levelCount: 1
        ))
        events.append(event(
            sourceIndex: 5,
            position: 2.5,
            duration: 0.5,
            levelCount: 1
        ))

        XCTAssertEqual(
            groupedIndices(
                timeSignature: timeSignature(beats: 6, unit: 8),
                events: events
            ),
            [[0, 1, 2], [4, 5]]
        )
    }

    func testGrouperSortsEventsByMusicalPositionBeforeGrouping() {
        let events = [
            event(sourceIndex: 2, position: 0.5, duration: 0.25, levelCount: 2),
            event(sourceIndex: 0, position: 0, duration: 0.25, levelCount: 2),
            event(sourceIndex: 3, position: 0.75, duration: 0.25, levelCount: 2),
            event(sourceIndex: 1, position: 0.25, duration: 0.25, levelCount: 2)
        ]

        XCTAssertEqual(
            groupedIndices(timeSignature: .fourFour, events: events),
            [[0, 1, 2, 3]]
        )
    }

    private func groupedIndices(
        timeSignature: TimeSignature,
        events: [NotationBeamGroupingEvent]
    ) -> [[Int]] {
        NotationBeamGrouper.groups(
            timeSignature: timeSignature,
            events: events
        ).map(\.eventIndices)
    }

    private func notes(
        count: Int,
        denominator: Int
    ) -> [NotationBeamGroupingEvent] {
        let duration = 4.0 / Double(denominator)
        return (0..<count).map { index in
            event(
                sourceIndex: index,
                position: Double(index) * duration,
                duration: duration,
                levelCount: denominator == 16 ? 2 : 1
            )
        }
    }

    private func event(
        sourceIndex: Int,
        position: Double,
        duration: Double,
        levelCount: Int,
        isRest: Bool = false
    ) -> NotationBeamGroupingEvent {
        NotationBeamGroupingEvent(
            sourceIndex: sourceIndex,
            positionInQuarterNotes: position,
            durationInQuarterNotes: duration,
            beamLevelCount: levelCount,
            isRest: isRest
        )
    }
}

private func timeSignature(beats: Int, unit: Int) -> TimeSignature {
    TimeSignature(beatsPerBar: beats, beatUnit: unit)
}
