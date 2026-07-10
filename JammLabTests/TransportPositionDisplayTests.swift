import XCTest
@testable import JammLab

final class TransportPositionDisplayTests: XCTestCase {
    func testDisplaysBarBeatHundredthsAndElapsedMilliseconds() {
        let tempoMap = makeTempoMap()

        XCTAssertEqual(displayText(time: 0, tempoMap: tempoMap), "1.1.00 / 0:00.000")
        XCTAssertEqual(displayText(time: 0.25, tempoMap: tempoMap), "1.1.50 / 0:00.250")
        XCTAssertEqual(displayText(time: 0.5, tempoMap: tempoMap), "1.2.00 / 0:00.500")
        XCTAssertEqual(displayText(time: 2, tempoMap: tempoMap), "2.1.00 / 0:02.000")
    }

    func testFloorsHundredthsJustBeforeBoundaryAndAdvancesAtBoundary() {
        let tempoMap = makeTempoMap()

        XCTAssertEqual(displayText(time: 0.5 - 0.0001, tempoMap: tempoMap), "1.1.99 / 0:00.500")
        XCTAssertEqual(displayText(time: 0.5, tempoMap: tempoMap), "1.2.00 / 0:00.500")
        XCTAssertEqual(displayText(time: 2 - 0.0001, tempoMap: tempoMap), "1.4.99 / 0:02.000")
        XCTAssertEqual(displayText(time: 2, tempoMap: tempoMap), "2.1.00 / 0:02.000")
    }

    func testPreservesPreFirstBeatBarNumbering() {
        let tempoMap = makeTempoMap(settings: BeatGridSettings(
            bpm: 120,
            firstBeatTime: 2,
            timeSignature: .fourFour
        ))

        XCTAssertEqual(displayText(time: 0, tempoMap: tempoMap), "-1.1.00 / 0:00.000")
        XCTAssertEqual(displayText(time: 1.5, tempoMap: tempoMap), "-1.4.00 / 0:01.500")
        XCTAssertEqual(displayText(time: 2, tempoMap: tempoMap), "1.1.00 / 0:02.000")
    }

    func testUsesTempoMapBarContinuityAndRestartMarkers() {
        let continuingMarker = TimecodedNote(
            time: 2,
            title: "3/4",
            metadata: TempoTimeSignatureMarkerPayload(beatsPerBar: 3).metadata
        )
        let continuingMap = makeTempoMap(markers: [continuingMarker])

        XCTAssertEqual(displayText(time: 2, tempoMap: continuingMap), "2.1.00 / 0:02.000")
        XCTAssertEqual(displayText(time: 3.5, tempoMap: continuingMap), "3.1.00 / 0:03.500")

        let restartingMarker = TimecodedNote(
            time: 2,
            title: "3/4",
            metadata: TempoTimeSignatureMarkerPayload(beatsPerBar: 3, setsNewFirstBeat: true).metadata
        )
        let restartingMap = makeTempoMap(markers: [restartingMarker])

        XCTAssertEqual(displayText(time: 2, tempoMap: restartingMap), "1.1.00 / 0:02.000")
    }

    func testFallsBackWhenTempoCannotProduceBeatDuration() {
        let noTempoMap = makeTempoMap(settings: BeatGridSettings())
        var infiniteTempoMap = makeTempoMap()
        infiniteTempoMap.segments = [
            TempoMapSegment(startTime: 0, endTime: 8, settings: BeatGridSettings(bpm: .infinity))
        ]
        var nanTempoMap = makeTempoMap()
        nanTempoMap.segments = [
            TempoMapSegment(startTime: 0, endTime: 8, settings: BeatGridSettings(bpm: .nan))
        ]

        XCTAssertEqual(displayText(time: 1, tempoMap: noTempoMap), "--.--.-- / 0:01.000")
        XCTAssertEqual(displayText(time: 1, tempoMap: infiniteTempoMap), "--.--.-- / 0:01.000")
        XCTAssertEqual(displayText(time: 1, tempoMap: nanTempoMap), "--.--.-- / 0:01.000")
    }

    func testInvalidPlaybackTimeClampsToZeroTimeDisplay() {
        let tempoMap = makeTempoMap()

        XCTAssertEqual(displayText(time: -1, tempoMap: tempoMap), "1.1.00 / 0:00.000")
        XCTAssertEqual(displayText(time: .nan, tempoMap: tempoMap), "1.1.00 / 0:00.000")
        XCTAssertEqual(displayText(time: .infinity, tempoMap: tempoMap), "1.1.00 / 0:00.000")
    }

    func testElapsedMillisecondsFormattingHandlesInvalidValuesAndRollover() {
        XCTAssertEqual(TimeFormatter.mmssMilliseconds(-1), "0:00.000")
        XCTAssertEqual(TimeFormatter.mmssMilliseconds(.nan), "0:00.000")
        XCTAssertEqual(TimeFormatter.mmssMilliseconds(.infinity), "0:00.000")
        XCTAssertEqual(TimeFormatter.mmssMilliseconds(61.234), "1:01.234")
        XCTAssertEqual(TimeFormatter.mmssMilliseconds(59.9996), "1:00.000")
    }

    private func displayText(time: TimeInterval, tempoMap: TempoMap) -> String {
        TransportPositionDisplay.make(time: time, tempoMap: tempoMap).displayText
    }

    private func makeTempoMap(
        settings: BeatGridSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour),
        markers: [TimecodedNote] = [],
        duration: TimeInterval = 8
    ) -> TempoMap {
        TempoMap(baseSettings: settings, markers: markers, duration: duration)
    }
}
