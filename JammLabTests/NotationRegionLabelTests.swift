import XCTest
@testable import JammLab

final class NotationRegionLabelTests: XCTestCase {
    func testNotationViewportStateBuildsRegionLabelsFromRegionAndLegacyLoopStarts() throws {
        let introID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let markerID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let verseID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let state = notationViewportState(
            tempoMap: fourFourTempoMap(duration: 8),
            currentTime: 0,
            visibleMeasureCount: 4,
            notes: [
                TimecodedNote(id: introID, kind: .region, time: 0.75, duration: 4, title: "Intro"),
                TimecodedNote(id: markerID, kind: .marker, time: 1, title: "Marker"),
                TimecodedNote(id: verseID, kind: .loop, time: 2.5, duration: 1, title: "Verse 1")
            ]
        )

        let introLabel = try XCTUnwrap(state.visibleMeasures[0].regionLabels.first)
        let verseLabel = try XCTUnwrap(state.visibleMeasures[1].regionLabels.first)

        XCTAssertEqual(state.visibleMeasures.flatMap(\.regionLabels).map(\.id), [introID, verseID])
        XCTAssertEqual(introLabel.measureNumber, 1)
        XCTAssertEqual(introLabel.offsetInQuarterNotes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(introLabel.title, "Intro")
        XCTAssertEqual(verseLabel.measureNumber, 2)
        XCTAssertEqual(verseLabel.offsetInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(verseLabel.title, "Verse 1")
    }

    func testNotationRegionLabelsUseRegionStartOnlyAndExcludeMeasureEnd() throws {
        let spanningID = UUID(uuidString: "00000000-0000-0000-0000-000000000304")!
        let boundaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000305")!
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 6),
            duration: 6,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notes: [
                TimecodedNote(id: spanningID, kind: .region, time: 1.75, duration: 3, title: "Bridge"),
                TimecodedNote(id: boundaryID, kind: .region, time: 2, duration: 0.5, title: "Verse")
            ]
        )

        XCTAssertEqual(state.measures[0].regionLabels.map(\.id), [spanningID])
        XCTAssertEqual(state.measures[1].regionLabels.map(\.id), [boundaryID])
        XCTAssertTrue(state.measures.dropFirst(2).allSatisfy { $0.regionLabels.isEmpty })
    }

    func testNotationRegionLabelsUseFallbackTitleForEmptyRegionNames() throws {
        let regionID = UUID(uuidString: "00000000-0000-0000-0000-000000000306")!
        let state = notationViewportState(
            tempoMap: fourFourTempoMap(duration: 4),
            currentTime: 0,
            notes: [
                TimecodedNote(id: regionID, kind: .region, time: 0, duration: 1, title: "   ")
            ]
        )

        let label = try XCTUnwrap(state.visibleMeasures[0].regionLabels.first)

        XCTAssertEqual(label.id, regionID)
        XCTAssertEqual(label.title, "Region")
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
        visibleMeasureCount: Int = 8,
        notes: [TimecodedNote] = []
    ) -> NotationViewportState {
        NotationViewportFactory().viewportState(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            currentTime: currentTime,
            playbackMarkerTime: 0,
            isPlaying: true,
            keyName: "C major",
            visibleMeasureCount: visibleMeasureCount,
            harmonySymbols: [],
            notes: notes
        )
    }
}
