import XCTest
@testable import JammLab

final class BeatGridAndTempoMapTests: XCTestCase {
    func testBeatGridFourBarsAt120BPMUsesExpectedBarStarts() {
        let settings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let markers = BeatGridCalculator().markers(settings: settings, visibleStartTime: 0, visibleEndTime: 8)
        let barStartTimes = markers.filter(\.isBarStart).map(\.time)

        XCTAssertEqual(barStartTimes, [0, 2, 4, 6, 8])
    }

    func testTimeSignatureNormalizesSupportedRangeAndBeatUnit() {
        XCTAssertEqual(TimeSignature(beatsPerBar: 0, beatUnit: 8), TimeSignature(beatsPerBar: 1, beatUnit: 4))
        XCTAssertEqual(TimeSignature(beatsPerBar: 9, beatUnit: 2), TimeSignature(beatsPerBar: 7, beatUnit: 4))
        XCTAssertEqual(BeatGridSettings(bpm: 120, timeSignature: TimeSignature(beatsPerBar: 9, beatUnit: 16)).clamped(to: 10).timeSignature.displayText, "7/4")
    }

    func testBeatGridUsesEditableBeatsPerBarForBarStarts() {
        let settings = BeatGridSettings(bpm: 120, timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4))
        let markers = BeatGridCalculator().markers(settings: settings, visibleStartTime: 0, visibleEndTime: 4.5)
        let barStartTimes = markers.filter(\.isBarStart).map(\.time)

        XCTAssertEqual(barStartTimes, [0, 1.5, 3.0, 4.5])
    }

    func testBeatGridUsesFirstBeatOffsetForBarsAndSnap() throws {
        let settings = BeatGridSettings(
            bpm: 120,
            firstBeatTime: 1.0,
            timeSignature: .fourFour
        )
        let calculator = BeatGridCalculator()

        let markers = calculator.markers(settings: settings, visibleStartTime: 0, visibleEndTime: 6)
        let barStarts = markers.filter(\.isBarStart)

        let firstBar = try XCTUnwrap(barStarts.first)
        let secondBar = try XCTUnwrap(barStarts.dropFirst().first)

        XCTAssertEqual(firstBar.time, 1.0, accuracy: 0.0001)
        XCTAssertEqual(firstBar.barNumber(beatsPerBar: 4), 1)
        XCTAssertEqual(secondBar.time, 3.0, accuracy: 0.0001)
        XCTAssertEqual(secondBar.barNumber(beatsPerBar: 4), 2)
        XCTAssertEqual(try XCTUnwrap(calculator.nearestBeatTime(to: 1.76, settings: settings, duration: 10)), 2.0, accuracy: 0.0001)
    }

    func testBeatGridIncludesNegativeBarsBeforeFirstBeat() throws {
        let settings = BeatGridSettings(
            bpm: 120,
            firstBeatTime: 2.0,
            timeSignature: .fourFour
        )
        let calculator = BeatGridCalculator()

        let markers = calculator.markers(settings: settings, visibleStartTime: 0, visibleEndTime: 2.1)
        let barStarts = markers.filter(\.isBarStart)

        XCTAssertEqual(markers.map(\.time), [0, 0.5, 1.0, 1.5, 2.0])
        XCTAssertEqual(barStarts.map(\.time), [0, 2.0])
        XCTAssertEqual(barStarts.compactMap { $0.barNumber(beatsPerBar: 4) }, [-1, 1])
        XCTAssertEqual(try XCTUnwrap(calculator.nearestBeatTime(to: 0.74, settings: settings, duration: 10)), 0.5, accuracy: 0.0001)
    }

    func testTempoTimeSignatureMarkerPayloadRoundTripsThroughMetadata() throws {
        let payload = TempoTimeSignatureMarkerPayload(
            bpm: 123.44,
            beatsPerBar: 9,
            beatUnit: 8,
            setsNewFirstBeat: true
        )
        let decoded = try XCTUnwrap(TempoTimeSignatureMarkerPayload(metadata: payload.metadata))

        XCTAssertEqual(try XCTUnwrap(decoded.bpm), 123.4, accuracy: 0.0001)
        XCTAssertEqual(decoded.beatsPerBar, 7)
        XCTAssertEqual(decoded.beatUnit, 4)
        XCTAssertTrue(decoded.setsNewFirstBeat)
        XCTAssertEqual(decoded.metadata[TempoTimeSignatureMarkerPayload.typeKey], TempoTimeSignatureMarkerPayload.typeValue)
        XCTAssertEqual(decoded.metadata[TempoTimeSignatureMarkerPayload.setsNewFirstBeatKey], "true")
        XCTAssertEqual(decoded.title, "123.4 BPM · 7/4")
        XCTAssertNil(TempoTimeSignatureMarkerPayload(metadata: [TempoTimeSignatureMarkerPayload.typeKey: TempoTimeSignatureMarkerPayload.typeValue]))
    }

    func testTempoTimeSignatureMarkerPayloadDefaultsNewFirstBeatToFalse() throws {
        let payload = try XCTUnwrap(TempoTimeSignatureMarkerPayload(metadata: [
            TempoTimeSignatureMarkerPayload.typeKey: TempoTimeSignatureMarkerPayload.typeValue,
            TempoTimeSignatureMarkerPayload.bpmKey: "120.0"
        ]))

        XCTAssertFalse(payload.setsNewFirstBeat)
    }

    func testTempoTimeSignatureMarkerPayloadAllowsNewFirstBeatOnlyMarker() throws {
        let payload = TempoTimeSignatureMarkerPayload(setsNewFirstBeat: true)
        let decoded = try XCTUnwrap(TempoTimeSignatureMarkerPayload(metadata: payload.metadata))

        XCTAssertNil(decoded.bpm)
        XCTAssertNil(decoded.beatsPerBar)
        XCTAssertTrue(decoded.setsNewFirstBeat)
        XCTAssertEqual(decoded.title, "New First Beat")
    }

    func testTempoMapContinuesBarNumberingByDefaultAndInheritsUnchangedValues() {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "3/4",
            metadata: TempoTimeSignatureMarkerPayload(beatsPerBar: 3).metadata
        )

        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 8)

        XCTAssertEqual(tempoMap.segments.count, 2)
        XCTAssertEqual(tempoMap.segments[0].startTime, 0, accuracy: 0.0001)
        XCTAssertEqual(tempoMap.segments[0].endTime, 2, accuracy: 0.0001)
        XCTAssertEqual(tempoMap.segments[0].settings.timeSignature, .fourFour)
        XCTAssertEqual(tempoMap.segments[1].startTime, 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(tempoMap.segments[1].settings.bpm), 120, accuracy: 0.0001)
        XCTAssertEqual(tempoMap.segments[1].settings.firstBeatTime, 2, accuracy: 0.0001)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 2)
        XCTAssertEqual(tempoMap.segments[1].settings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
    }

    func testTempoMapRestartsBarNumberingWhenMarkerSetsNewFirstBeat() {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "3/4",
            metadata: TempoTimeSignatureMarkerPayload(beatsPerBar: 3, setsNewFirstBeat: true).metadata
        )

        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 8)

        XCTAssertEqual(tempoMap.segments[1].settings.firstBeatTime, 2, accuracy: 0.0001)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 1)
        XCTAssertEqual(tempoMap.segments[1].settings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
    }

    func testBeatGridCalculatorUsesTempoMapSegmentsWithoutBoundaryDuplicates() throws {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "60 BPM · 3/4",
            metadata: TempoTimeSignatureMarkerPayload(bpm: 60, beatsPerBar: 3).metadata
        )
        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 6)

        let markers = BeatGridCalculator().markers(tempoMap: tempoMap, visibleStartTime: 0, visibleEndTime: 6)

        XCTAssertEqual(markers.map(\.time), [0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0])
        XCTAssertEqual(markers.filter { $0.time == 2.0 }.count, 1)
        XCTAssertTrue(try XCTUnwrap(markers.first { $0.time == 2.0 }).isBarStart)
    }

    func testTempoMapSnappingUsesPostMarkerTempoAfterMarker() throws {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "60 BPM",
            metadata: TempoTimeSignatureMarkerPayload(bpm: 60).metadata
        )
        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 6)

        XCTAssertEqual(try XCTUnwrap(BeatGridCalculator().nearestBeatTime(to: 2.6, tempoMap: tempoMap)), 3.0, accuracy: 0.0001)
    }
}
