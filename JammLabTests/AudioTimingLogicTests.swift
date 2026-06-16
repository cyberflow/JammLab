import AVFoundation
import XCTest
@testable import JammLab

final class AudioTimingLogicTests: XCTestCase {
    func testDecodedAudioDurationUsesPCMFrameLength() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jammlab-duration-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050)!
        buffer.frameLength = 22_050
        try file.write(from: buffer)

        let duration = try AudioFileImporter.decodedDuration(for: url)

        XCTAssertEqual(duration, 0.5, accuracy: 0.0001)
    }

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

    func testClickDelayLineDelaysSamplesByConfiguredFrameCount() {
        var delayLine = ClickDelayLine()
        delayLine.setDelayFrames(3)

        let output = [1, 2, 3, 4, 5].map { delayLine.process(Float($0)) }

        XCTAssertEqual(output, [0, 0, 0, 1, 2])

        delayLine.setDelayFrames(0)
        XCTAssertEqual(delayLine.process(9), 9)
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

    func testMetronomeClickSchedulerUsesFirstBeatOffsetAndAccents() throws {
        let settings = BeatGridSettings(
            bpm: 120,
            firstBeatTime: 1.0,
            timeSignature: .fourFour
        )
        let scheduler = MetronomeClickScheduler()

        let events = scheduler.events(settings: settings, segmentStartTime: 0, segmentEndTime: 3.1)

        XCTAssertEqual(events.map(\.sourceTime), [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0])
        XCTAssertEqual(events.map(\.kind), [.regular, .regular, .accent, .regular, .regular, .regular, .accent])
    }

    func testMetronomeClickSchedulerAccentsNegativeBarStarts() {
        let settings = BeatGridSettings(
            bpm: 120,
            firstBeatTime: 2.0,
            timeSignature: .fourFour
        )
        let scheduler = MetronomeClickScheduler()

        let events = scheduler.events(settings: settings, segmentStartTime: 0, segmentEndTime: 2.1)

        XCTAssertEqual(events.map(\.sourceTime), [0, 0.5, 1.0, 1.5, 2.0])
        XCTAssertEqual(events.map(\.kind), [.accent, .regular, .regular, .regular, .accent])
    }

    func testMetronomeClickSchedulerAccentsBarStarts() {
        let settings = BeatGridSettings(
            bpm: 120,
            firstBeatTime: 0,
            timeSignature: .fourFour
        )
        let scheduler = MetronomeClickScheduler()

        let events = scheduler.events(settings: settings, segmentStartTime: 0, segmentEndTime: 2.1)

        XCTAssertEqual(events.map(\.sourceTime), [0, 0.5, 1.0, 1.5, 2.0])
        XCTAssertEqual(events.map(\.kind), [.accent, .regular, .regular, .regular, .accent])
    }

    func testMetronomeClickSchedulerAccentsEditableBarStarts() {
        let settings = BeatGridSettings(
            bpm: 120,
            firstBeatTime: 0,
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4)
        )
        let scheduler = MetronomeClickScheduler()

        let events = scheduler.events(settings: settings, segmentStartTime: 0, segmentEndTime: 1.6)

        XCTAssertEqual(events.map(\.sourceTime), [0, 0.5, 1.0, 1.5])
        XCTAssertEqual(events.map(\.kind), [.accent, .regular, .regular, .accent])
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

    func testMetronomeClickSchedulerSwitchesTempoMapAtMarker() {
        let baseSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        let tempoMarker = TimecodedNote(
            time: 2,
            title: "60 BPM · 3/4",
            metadata: TempoTimeSignatureMarkerPayload(bpm: 60, beatsPerBar: 3).metadata
        )
        let tempoMap = TempoMap(baseSettings: baseSettings, markers: [tempoMarker], duration: 6)

        let events = MetronomeClickScheduler().events(tempoMap: tempoMap, segmentStartTime: 0, segmentEndTime: 5.1)

        XCTAssertEqual(events.map(\.sourceTime), [0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0])
        XCTAssertEqual(events.map(\.kind), [.accent, .regular, .regular, .regular, .accent, .regular, .regular, .accent])
    }

    func testMetronomeClickSchedulerStartsAfterSeekSegment() {
        let settings = BeatGridSettings(
            bpm: 120,
            firstBeatTime: 0,
            timeSignature: .fourFour
        )
        let scheduler = MetronomeClickScheduler()

        let events = scheduler.events(settings: settings, segmentStartTime: 1.25, segmentEndTime: 2.1)

        XCTAssertEqual(events.map(\.sourceTime), [1.5, 2.0])
        XCTAssertEqual(events.map(\.kind), [.regular, .accent])
    }

    func testMetronomeClickSchedulerRequiresTempo() {
        let scheduler = MetronomeClickScheduler()

        let events = scheduler.events(settings: BeatGridSettings(), segmentStartTime: 0, segmentEndTime: 4)

        XCTAssertTrue(events.isEmpty)
    }

    func testTempoGridCalculatorComputesBeatAndBarDurations() {
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

    func testTempoGridCalculatorUsesEditableTimeSignatureForBarDuration() {
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

    func testTempoGridCalculatorFormatsBarAndTimeLabels() throws {
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

    func testTempoGridCalculatorContinuesLabelsAtTempoMarkerByDefault() {
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

    func testTempoGridCalculatorRestartsLabelsWhenMarkerSetsNewFirstBeat() {
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

    func testTempoGridCalculatorChoosesBarStepFromLabelSpacing() {
        XCTAssertEqual(TempoGridCalculator.barStep(for: 100, minimumLabelSpacing: 86), 1)
        XCTAssertEqual(TempoGridCalculator.barStep(for: 30, minimumLabelSpacing: 86), 4)
        XCTAssertEqual(TempoGridCalculator.barStep(for: 2, minimumLabelSpacing: 86), 32)
    }

    func testTempoGridCalculatorAdaptsLabelsToZoomLevel() {
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

    func testTempoGridCalculatorBeatMarkersRespectPixelThreshold() {
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

    func testTempoGridCalculatorFormatsTrackTime() {
        XCTAssertEqual(TempoGridCalculator.formatTime(0), "0:00.00")
        XCTAssertEqual(TempoGridCalculator.formatTime(2.66), "0:02.66")
        XCTAssertEqual(TempoGridCalculator.formatTime(21.33), "0:21.33")
    }

    func testMetronomeClickTimingMapperMapsSegmentStartToZero() throws {
        let mapper = MetronomeClickTimingMapper()
        let event = MetronomeClickEvent(sourceTime: 4, kind: .accent)

        let sampleTime = try XCTUnwrap(mapper.sampleTime(
            for: event,
            segmentStartTime: 4,
            playbackRate: 1,
            sampleRate: 44_100
        ))

        XCTAssertEqual(sampleTime, 0)
    }

    func testMetronomeClickTimingMapperRejectsEventsBeforeSeekSegment() {
        let mapper = MetronomeClickTimingMapper()
        let event = MetronomeClickEvent(sourceTime: 3.9, kind: .regular)

        let sampleTime = mapper.sampleTime(
            for: event,
            segmentStartTime: 4,
            playbackRate: 1,
            sampleRate: 44_100
        )

        XCTAssertNil(sampleTime)
    }

    func testMetronomeClickTimingMapperUsesAudiblePlaybackRate() throws {
        let mapper = MetronomeClickTimingMapper()
        let event = MetronomeClickEvent(sourceTime: 5, kind: .regular)

        let sampleTime = try XCTUnwrap(mapper.sampleTime(
            for: event,
            segmentStartTime: 4,
            playbackRate: 0.5,
            sampleRate: 1_000
        ))

        XCTAssertEqual(sampleTime, 2_000)
    }

}
