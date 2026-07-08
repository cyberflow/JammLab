import XCTest
@testable import JammLab

final class NotationHarmonyPlacementTests: XCTestCase {
    func testNotationViewportAttachesHarmonySymbolsToVisibleMeasures() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let state = notationViewportState(
            tempoMap: fourFourTempoMap(duration: 8),
            currentTime: 0.1,
            visibleMeasureCount: 2,
            harmonySymbols: [
                HarmonySymbol(
                    id: firstID,
                    time: 0.75,
                    measureNumber: 99,
                    offsetInQuarterNotes: 99,
                    rawText: "Cmaj7"
                ),
                HarmonySymbol(
                    id: secondID,
                    time: 2.5,
                    measureNumber: 1,
                    offsetInQuarterNotes: 0,
                    rawText: "G7"
                )
            ]
        )

        let firstHarmony = try XCTUnwrap(state.visibleMeasures[0].harmonies.first)
        let secondHarmony = try XCTUnwrap(state.visibleMeasures[1].harmonies.first)

        XCTAssertEqual(firstHarmony.id, firstID)
        XCTAssertEqual(firstHarmony.measureNumber, 1)
        XCTAssertEqual(firstHarmony.offsetInQuarterNotes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(firstHarmony.rawText, "Cmaj7")
        XCTAssertEqual(secondHarmony.id, secondID)
        XCTAssertEqual(secondHarmony.measureNumber, 2)
        XCTAssertEqual(secondHarmony.offsetInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(secondHarmony.rawText, "G7")
    }

    func testHarmonyPlacementUsesExactTimeAndNavigatesAcrossNotationItems() throws {
        let factory = NotationViewportFactory()
        let tempoMap = fourFourTempoMap(duration: 8)
        let notationItems = [
            NotationMeasureItem(
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                measureNumber: 2,
                measureStartTime: 2,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 1)
            )
        ]

        let placement = try XCTUnwrap(factory.harmonyPlacement(
            for: 0.87,
            tempoMap: tempoMap,
            duration: 8
        ))
        let nextMeasure = try XCTUnwrap(factory.adjacentHarmonyPlacement(
            from: 0,
            direction: .next,
            tempoMap: tempoMap,
            duration: 8,
            notationItems: notationItems
        ))
        let previousMeasure = try XCTUnwrap(factory.adjacentHarmonyPlacement(
            from: 2,
            direction: .previous,
            tempoMap: tempoMap,
            duration: 8,
            notationItems: notationItems
        ))

        XCTAssertEqual(placement.measureNumber, 1)
        XCTAssertEqual(placement.offsetInQuarterNotes, 1.74, accuracy: 0.0001)
        XCTAssertEqual(placement.time, 0.87, accuracy: 0.0001)
        XCTAssertEqual(nextMeasure.measureNumber, 1)
        XCTAssertEqual(nextMeasure.offsetInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(nextMeasure.time, 0.5, accuracy: 0.0001)
        XCTAssertEqual(previousMeasure.measureNumber, 1)
        XCTAssertEqual(previousMeasure.offsetInQuarterNotes, 2, accuracy: 0.0001)
        XCTAssertEqual(previousMeasure.time, 1, accuracy: 0.0001)
    }

    private func fourFourTempoMap(duration: TimeInterval) -> TempoMap {
        TempoMap(
            baseSettings: BeatGridSettings(
                bpm: 120,
                firstBeatTime: 0,
                timeSignature: .fourFour
            ),
            markers: [],
            duration: duration
        )
    }

    private func notationViewportState(
        tempoMap: TempoMap,
        currentTime: TimeInterval,
        visibleMeasureCount: Int,
        harmonySymbols: [HarmonySymbol]
    ) -> NotationViewportState {
        NotationViewportFactory().viewportState(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            currentTime: currentTime,
            playbackMarkerTime: 0,
            isPlaying: true,
            keyName: "C major",
            visibleMeasureCount: visibleMeasureCount,
            harmonySymbols: harmonySymbols,
            notes: []
        )
    }
}
