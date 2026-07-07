import XCTest
@testable import JammLab

final class NotationViewportTests: XCTestCase {
    func testNotationViewportUsesCurrentTimeWhilePlayingAndMarkerTimeWhenStopped() {
        let tempoMap = fourFourTempoMap(duration: 60)

        let playingState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 10.2,
            playbackMarkerTime: 2.1,
            isPlaying: true,
            visibleMeasureCount: 4
        )
        let stoppedState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 10.2,
            playbackMarkerTime: 2.1,
            isPlaying: false,
            visibleMeasureCount: 4
        )

        XCTAssertEqual(playingState.firstVisibleMeasureNumber, 5)
        XCTAssertEqual(playingState.activeMeasureNumber, 6)
        XCTAssertEqual(stoppedState.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(stoppedState.activeMeasureNumber, 2)
    }

    func testNotationViewportStartsAtCurrentMeasurePage() {
        let state = notationViewportState(
            tempoMap: fourFourTempoMap(duration: 120),
            currentTime: 40.25,
            visibleMeasureCount: 8
        )

        XCTAssertEqual(state.firstVisibleMeasureNumber, 17)
        XCTAssertEqual(state.activeMeasureNumber, 21)
        XCTAssertEqual(state.visibleMeasures.map(\.number), [17, 18, 19, 20, 21, 22, 23, 24])
        XCTAssertEqual(state.visibleMeasureCount, 8)
    }

    func testNotationViewportKeepsPageUntilPlaybackEntersNextPage() {
        let tempoMap = fourFourTempoMap(duration: 120)

        let measureEightState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 14.1,
            visibleMeasureCount: 8
        )
        let measureNineState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 16.1,
            visibleMeasureCount: 8
        )

        XCTAssertEqual(measureEightState.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(measureEightState.activeMeasureNumber, 8)
        XCTAssertEqual(measureNineState.firstVisibleMeasureNumber, 9)
        XCTAssertEqual(measureNineState.activeMeasureNumber, 9)
        XCTAssertEqual(measureNineState.visibleMeasures.map(\.number), [9, 10, 11, 12, 13, 14, 15, 16])
    }

    func testNotationViewportStartsAtMeasureOneWhenTrackStartsAtZero() throws {
        let state = notationViewportState(
            tempoMap: fourFourTempoMap(duration: 120),
            currentTime: 0,
            playbackMarkerTime: 0,
            visibleMeasureCount: 8
        )
        let firstMeasure = try XCTUnwrap(state.visibleMeasures.first)

        XCTAssertEqual(state.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(state.activeMeasureNumber, 1)
        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(firstMeasure.startTime, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(firstMeasure.duration, 0)
    }

    func testNotationViewportStartsAtMeasureOneBeforeDelayedFirstBeat() throws {
        let tempoMap = fourFourTempoMap(duration: 120, firstBeatTime: 0.78)

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 0,
            playbackMarkerTime: 0,
            visibleMeasureCount: 8
        )
        let firstMeasure = try XCTUnwrap(state.visibleMeasures.first)

        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(state.activeMeasureNumber, 1)
        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(state.anchorTime, 0.78, accuracy: 0.0001)
        XCTAssertEqual(firstMeasure.startTime, 0.78, accuracy: 0.0001)
        XCTAssertGreaterThan(firstMeasure.duration, 0)
    }

    func testNotationViewportKeepsMeasureOneAtDelayedFirstBeat() {
        let tempoMap = fourFourTempoMap(duration: 120, firstBeatTime: 0.78)

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 0.78,
            playbackMarkerTime: 0,
            visibleMeasureCount: 8
        )

        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(state.activeMeasureNumber, 1)
        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(state.anchorTime, 0.78, accuracy: 0.0001)
    }

    func testNotationViewportKeepsFirstPageInsideSecondDelayedMeasure() {
        let tempoMap = fourFourTempoMap(duration: 120, firstBeatTime: 0.78)

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 3.0,
            playbackMarkerTime: 0,
            visibleMeasureCount: 8
        )

        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(state.activeMeasureNumber, 2)
        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testNotationViewportCarriesMeasureAttributesAcrossTimeSignatureMarker() {
        let tempoMap = fourFourTempoMap(
            duration: 12,
            markers: [timeSignatureMarker(time: 4, beatsPerBar: 3)]
        )

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 2.1,
            visibleMeasureCount: 4
        )

        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(state.visibleMeasures[0].attributes.timeSignature, .fourFour)
        XCTAssertEqual(state.visibleMeasures[2].attributes.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
    }

    func testNotationViewportDoesNotRestartPageAtTimeSignatureMarkerInsideVisibleWindow() {
        let tempoMap = fourFourTempoMap(
            duration: 18,
            markers: [timeSignatureMarker(time: 4, beatsPerBar: 3)]
        )

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 5.1,
            visibleMeasureCount: 8
        )

        XCTAssertEqual(state.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(state.activeMeasureNumber, 3)
        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testNotationViewportHonorsBarNumberResetAtTimeSignatureMarker() {
        let tempoMap = fourFourTempoMap(
            duration: 12,
            markers: [timeSignatureMarker(time: 4, beatsPerBar: 3, setsNewFirstBeat: true)]
        )

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 2.1,
            visibleMeasureCount: 4
        )

        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 1, 2])
    }

    func testNotationViewportKeepsGlobalPageAcrossBarNumberReset() {
        let tempoMap = fourFourTempoMap(
            duration: 18,
            markers: [timeSignatureMarker(time: 4, beatsPerBar: 3, setsNewFirstBeat: true)]
        )

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 5.1,
            visibleMeasureCount: 8
        )

        XCTAssertEqual(state.firstVisibleMeasureNumber, 1)
        XCTAssertEqual(state.activeMeasureNumber, 1)
        XCTAssertEqual(state.visibleMeasures.map(\.number), [1, 2, 1, 2, 3, 4, 5, 6])
    }

    func testNotationViewportReturnsPendingStateWhenTempoIsUnavailable() {
        let tempoMap = TempoMap(baseSettings: BeatGridSettings(), markers: [], duration: 12)

        let state = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 2,
            playbackMarkerTime: 2,
            visibleMeasureCount: 8
        )

        XCTAssertFalse(state.isReady)
        XCTAssertTrue(state.visibleMeasures.isEmpty)
        XCTAssertEqual(state.visibleMeasureCount, 8)
    }

    func testNotationViewportKeepsActiveMeasureVisibleWhenVisibleCountChanges() throws {
        let tempoMap = fourFourTempoMap(duration: 120)

        let eightCountState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 14.1,
            visibleMeasureCount: 8
        )
        let sevenCountState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 14.1,
            visibleMeasureCount: 7
        )
        let fourCountState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 8.1,
            visibleMeasureCount: 4
        )
        let threeCountState = notationViewportState(
            tempoMap: tempoMap,
            currentTime: 8.1,
            visibleMeasureCount: 3
        )

        XCTAssertTrue(eightCountState.visibleMeasures.map(\.number).contains(try XCTUnwrap(eightCountState.activeMeasureNumber)))
        XCTAssertTrue(sevenCountState.visibleMeasures.map(\.number).contains(try XCTUnwrap(sevenCountState.activeMeasureNumber)))
        XCTAssertTrue(fourCountState.visibleMeasures.map(\.number).contains(try XCTUnwrap(fourCountState.activeMeasureNumber)))
        XCTAssertTrue(threeCountState.visibleMeasures.map(\.number).contains(try XCTUnwrap(threeCountState.activeMeasureNumber)))
    }

    private func fourFourTempoMap(
        duration: TimeInterval,
        firstBeatTime: TimeInterval = 0,
        markers: [TimecodedNote] = []
    ) -> TempoMap {
        TempoMap(
            baseSettings: BeatGridSettings(
                bpm: 120,
                firstBeatTime: firstBeatTime,
                timeSignature: .fourFour
            ),
            markers: markers,
            duration: duration
        )
    }

    private func notationViewportState(
        tempoMap: TempoMap,
        currentTime: TimeInterval,
        playbackMarkerTime: TimeInterval = 0,
        isPlaying: Bool = true,
        keyName: String? = "C major",
        visibleMeasureCount: Int = 8,
        harmonySymbols: [HarmonySymbol] = [],
        notes: [TimecodedNote] = []
    ) -> NotationViewportState {
        NotationViewportFactory().viewportState(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            currentTime: currentTime,
            playbackMarkerTime: playbackMarkerTime,
            isPlaying: isPlaying,
            keyName: keyName,
            visibleMeasureCount: visibleMeasureCount,
            harmonySymbols: harmonySymbols,
            notes: notes
        )
    }

    private func timeSignatureMarker(
        time: TimeInterval,
        beatsPerBar: Int,
        setsNewFirstBeat: Bool = false
    ) -> TimecodedNote {
        TimecodedNote(
            time: time,
            title: "\(beatsPerBar)/4",
            metadata: TempoTimeSignatureMarkerPayload(
                beatsPerBar: beatsPerBar,
                setsNewFirstBeat: setsNewFirstBeat
            ).metadata
        )
    }
}
