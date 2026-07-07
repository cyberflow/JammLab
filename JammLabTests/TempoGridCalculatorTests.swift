import XCTest
@testable import JammLab

final class TempoGridCalculatorTests: XCTestCase {
    func testComputesBeatAndBarDurations() {
        let calculator = TempoGridCalculator()
        let result = calculator.grid(
            settings: BeatGridSettings(bpm: 120, timeSignature: .fourFour),
            viewport: TimelineViewport(duration: 20, visibleRange: 0...20),
            width: 1_000,
            minimumLabelSpacing: 86
        )

        XCTAssertEqual(result.secondsPerBeat, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.secondsPerBar, 2.0, accuracy: 0.0001)
    }

    func testUsesEditableTimeSignatureForBarDuration() {
        let calculator = TempoGridCalculator()
        let result = calculator.grid(
            settings: BeatGridSettings(bpm: 120, timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4)),
            viewport: TimelineViewport(duration: 20, visibleRange: 0...20),
            width: 1_000,
            minimumLabelSpacing: 86
        )

        XCTAssertEqual(result.secondsPerBeat, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.secondsPerBar, 1.5, accuracy: 0.0001)
    }

    func testFormatsBarAndTimeLabels() throws {
        let calculator = TempoGridCalculator()
        let result = calculator.grid(
            settings: BeatGridSettings(bpm: 120, firstBeatTime: 2, timeSignature: .fourFour),
            viewport: TimelineViewport(duration: 24, visibleRange: 0...8),
            width: 800,
            minimumLabelSpacing: 80
        )

        let labeledMarkers = result.markers.filter { $0.kind == .majorLabeled }

        XCTAssertEqual(labeledMarkers.map(\.barBeatLabel), ["-1.1", "1.1", "2.1", "3.1", "4.1"])
        XCTAssertEqual(labeledMarkers.map(\.timeLabel), ["0:00.00", "0:02.00", "0:04.00", "0:06.00", "0:08.00"])
        XCTAssertEqual(try XCTUnwrap(labeledMarkers.first?.xPosition), 0, accuracy: 0.0001)
    }

    func testContinuesLabelsAtTempoMarkerByDefault() {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "60 BPM · 3/4",
            metadata: TempoTimeSignatureMarkerPayload(bpm: 60, beatsPerBar: 3).metadata
        )
        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 6)

        let result = TempoGridCalculator().grid(
            tempoMap: tempoMap,
            viewport: TimelineViewport(duration: 6, visibleRange: 0...6),
            width: 600,
            minimumLabelSpacing: 20
        )
        let labeledMarkers = result.markers.filter { $0.kind == .majorLabeled }

        XCTAssertEqual(labeledMarkers.map(\.time), [0, 2, 5])
        XCTAssertEqual(labeledMarkers.map(\.barBeatLabel), ["1.1", "2.1", "3.1"])
    }

    func testRestartsLabelsWhenMarkerSetsNewFirstBeat() {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "60 BPM · 3/4",
            metadata: TempoTimeSignatureMarkerPayload(bpm: 60, beatsPerBar: 3, setsNewFirstBeat: true).metadata
        )
        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 6)

        let result = TempoGridCalculator().grid(
            tempoMap: tempoMap,
            viewport: TimelineViewport(duration: 6, visibleRange: 0...6),
            width: 600,
            minimumLabelSpacing: 20
        )
        let labeledMarkers = result.markers.filter { $0.kind == .majorLabeled }

        XCTAssertEqual(labeledMarkers.map(\.time), [0, 2, 5])
        XCTAssertEqual(labeledMarkers.map(\.barBeatLabel), ["1.1", "1.1", "2.1"])
    }

    func testChoosesBarStepFromLabelSpacing() {
        XCTAssertEqual(TempoGridCalculator.barStep(for: 100, minimumLabelSpacing: 86), 1)
        XCTAssertEqual(TempoGridCalculator.barStep(for: 30, minimumLabelSpacing: 86), 4)
        XCTAssertEqual(TempoGridCalculator.barStep(for: 2, minimumLabelSpacing: 86), 32)
    }

    func testAdaptsLabelsToZoomLevel() {
        let calculator = TempoGridCalculator()
        let settings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let zoomedIn = calculator.grid(
            settings: settings,
            viewport: TimelineViewport(duration: 120, visibleRange: 0...16),
            width: 800,
            minimumLabelSpacing: 86
        )
        let zoomedOut = calculator.grid(
            settings: settings,
            viewport: TimelineViewport(duration: 120, visibleRange: 0...120),
            width: 800,
            minimumLabelSpacing: 86
        )

        XCTAssertEqual(zoomedIn.barStep, 1)
        XCTAssertGreaterThan(zoomedOut.barStep, zoomedIn.barStep)
        XCTAssertLessThan(
            zoomedOut.markers.filter { $0.kind == .majorLabeled }.count,
            zoomedIn.markers.filter { $0.kind == .majorLabeled }.count
        )
    }

    func testBeatMarkersRespectPixelThreshold() {
        let calculator = TempoGridCalculator()
        let settings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let dense = calculator.grid(
            settings: settings,
            viewport: TimelineViewport(duration: 8, visibleRange: 0...8),
            width: 800,
            minimumLabelSpacing: 86
        )
        let sparse = calculator.grid(
            settings: settings,
            viewport: TimelineViewport(duration: 120, visibleRange: 0...120),
            width: 800,
            minimumLabelSpacing: 86
        )

        XCTAssertFalse(dense.markers.filter { $0.kind == .beat }.isEmpty)
        XCTAssertTrue(sparse.markers.filter { $0.kind == .beat }.isEmpty)
    }

    func testFormatsTrackTime() {
        XCTAssertEqual(TempoGridCalculator.formatTime(0), "0:00.00")
        XCTAssertEqual(TempoGridCalculator.formatTime(2.66), "0:02.66")
        XCTAssertEqual(TempoGridCalculator.formatTime(21.33), "0:21.33")
    }
}
