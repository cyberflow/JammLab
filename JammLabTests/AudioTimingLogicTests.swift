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

    func testNotationVisibleMeasureFitterChoosesCountForAvailableWidth() {
        let minimumWidth = AppTheme.Timeline.notationMeasureMinWidth
        let stateForMeasureCount: (Int) -> NotationViewportState = {
            NotationViewportState.pending(visibleMeasureCount: $0)
        }

        XCTAssertEqual(
            NotationVisibleMeasureFitter.fittedMeasureCount(
                availableWidth: minimumWidth * 8,
                maximumMeasureCount: 8,
                stateForMeasureCount: stateForMeasureCount
            ),
            8
        )
        XCTAssertEqual(
            NotationVisibleMeasureFitter.fittedMeasureCount(
                availableWidth: minimumWidth * 4 + 10,
                maximumMeasureCount: 8,
                stateForMeasureCount: stateForMeasureCount
            ),
            4
        )
        XCTAssertEqual(
            NotationVisibleMeasureFitter.fittedMeasureCount(
                availableWidth: minimumWidth * 0.5,
                maximumMeasureCount: 8,
                stateForMeasureCount: stateForMeasureCount
            ),
            1
        )
    }

    func testNotationVisibleMeasureFitterAccountsForAttributeReserveWidth() {
        let tempoMap = fourFourTempoMap(duration: 120)
        let availableWidth = AppTheme.Timeline.notationMeasureMinWidth * 4
        let stateForMeasureCount: (Int) -> NotationViewportState = { count in
            self.notationViewportState(
                tempoMap: tempoMap,
                currentTime: 0,
                keyName: "D major",
                visibleMeasureCount: count
            )
        }

        let fittedCount = NotationVisibleMeasureFitter.fittedMeasureCount(
            availableWidth: availableWidth,
            maximumMeasureCount: 4,
            stateForMeasureCount: stateForMeasureCount
        )
        let fittedState = stateForMeasureCount(fittedCount)
        let fourMeasureState = stateForMeasureCount(4)

        XCTAssertLessThan(fittedCount, 4)
        XCTAssertLessThanOrEqual(
            NotationVisibleMeasureFitter.minimumRequiredWidth(for: fittedState),
            availableWidth + NotationVisibleMeasureFitter.widthTolerance
        )
        XCTAssertGreaterThan(
            NotationVisibleMeasureFitter.minimumRequiredWidth(for: fourMeasureState),
            availableWidth + NotationVisibleMeasureFitter.widthTolerance
        )
    }

    func testNotationVisibleMeasureFitterFallsBackToOneWhenPreferredSingleMeasureIsTooWide() {
        let tempoMap = fourFourTempoMap(duration: 120)
        let availableWidth: CGFloat = 10
        let stateForMeasureCount: (Int) -> NotationViewportState = { count in
            self.notationViewportState(
                tempoMap: tempoMap,
                currentTime: 0,
                keyName: "D major",
                visibleMeasureCount: count
            )
        }

        let fittedCount = NotationVisibleMeasureFitter.fittedMeasureCount(
            availableWidth: availableWidth,
            maximumMeasureCount: 8,
            stateForMeasureCount: stateForMeasureCount
        )

        XCTAssertEqual(fittedCount, 1)
        XCTAssertGreaterThan(
            NotationVisibleMeasureFitter.minimumRequiredWidth(for: stateForMeasureCount(1)),
            availableWidth
        )
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

    func testNotationScoreStateBuildsWholeDurationAndSystems() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 8),
            duration: 8,
            currentTime: 4.1,
            playbackMarkerTime: 1,
            isPlaying: true,
            keyName: "G major"
        )

        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.measures.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(state.measures.map(\.attributes.keySignature).map(\.fifths), [1, 1, 1, 1])
        XCTAssertEqual(state.activeMeasureNumber, 3)
        XCTAssertEqual(state.anchorTime, 4.1, accuracy: 0.0001)

        let systems = state.systems(measuresPerSystem: 2)
        XCTAssertEqual(systems.count, 2)
        XCTAssertEqual(systems[0].viewportState.visibleMeasures.map(\.number), [1, 2])
        XCTAssertEqual(systems[1].viewportState.visibleMeasures.map(\.number), [3, 4])
        XCTAssertEqual(systems[1].viewportState.activeMeasureNumber, 3)
    }

    func testNotationScoreStateUsesPlaybackMarkerWhenNotPlayingAndClampsAtEnd() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 8),
            duration: 8,
            currentTime: 6,
            playbackMarkerTime: 20,
            isPlaying: false,
            keyName: "C major"
        )

        XCTAssertEqual(state.activeMeasureNumber, 4)
        XCTAssertLessThan(state.anchorTime, 8)
        XCTAssertGreaterThan(state.anchorTime, 7.9)
    }

    func testNotationScoreStateTracksTimeSignatureMarkersAndHarmonies() throws {
        let harmonyID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(
                duration: 8,
                markers: [timeSignatureMarker(time: 4, beatsPerBar: 3)]
            ),
            duration: 8,
            currentTime: 5,
            playbackMarkerTime: 0,
            isPlaying: true,
            keyName: "C major",
            harmonySymbols: [
                HarmonySymbol(
                    id: harmonyID,
                    time: 5,
                    measureNumber: 99,
                    offsetInQuarterNotes: 99,
                    rawText: "Dm7"
                )
            ]
        )

        XCTAssertEqual(state.measures.map(\.attributes.timeSignature.beatsPerBar), [4, 4, 3, 3, 3])
        let harmony = try XCTUnwrap(state.measures.flatMap(\.harmonies).first)
        XCTAssertEqual(harmony.id, harmonyID)
        XCTAssertEqual(harmony.measureNumber, 3)
        XCTAssertEqual(harmony.rawText, "Dm7")
    }

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

    func testNotationScoreStateIsPendingForZeroDuration() {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 0),
            duration: 0,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "D major"
        )

        XCTAssertFalse(state.isReady)
        XCTAssertTrue(state.measures.isEmpty)
        XCTAssertEqual(state.keySignature.fifths, 2)
    }

    func testHarmonyPlacementSnapsToResolutionAndNavigatesAcrossMeasures() throws {
        let factory = NotationViewportFactory()
        let tempoMap = fourFourTempoMap(duration: 8)
        let resolution = HarmonyInputResolution(denominator: 4)

        let placement = try XCTUnwrap(factory.harmonyPlacement(
            for: 0.87,
            tempoMap: tempoMap,
            duration: 8,
            resolution: resolution
        ))
        let nextMeasure = try XCTUnwrap(factory.adjacentHarmonyPlacement(
            from: 1.5,
            direction: .next,
            tempoMap: tempoMap,
            duration: 8,
            resolution: resolution
        ))
        let previousMeasure = try XCTUnwrap(factory.adjacentHarmonyPlacement(
            from: 2,
            direction: .previous,
            tempoMap: tempoMap,
            duration: 8,
            resolution: resolution
        ))

        XCTAssertEqual(placement.measureNumber, 1)
        XCTAssertEqual(placement.offsetInQuarterNotes, 2, accuracy: 0.0001)
        XCTAssertEqual(placement.time, 1, accuracy: 0.0001)
        XCTAssertEqual(nextMeasure.measureNumber, 2)
        XCTAssertEqual(nextMeasure.offsetInQuarterNotes, 0, accuracy: 0.0001)
        XCTAssertEqual(nextMeasure.time, 2, accuracy: 0.0001)
        XCTAssertEqual(previousMeasure.measureNumber, 1)
        XCTAssertEqual(previousMeasure.offsetInQuarterNotes, 3, accuracy: 0.0001)
        XCTAssertEqual(previousMeasure.time, 1.5, accuracy: 0.0001)
    }

    func testNotationKeySignatureParsingSupportsCommonDetectedKeysAndFallback() {
        let fSharpMinor = KeySignature.normalized(from: "F# minor")
        let bFlatMajor = KeySignature.normalized(from: "Bb major")
        let aMinor = KeySignature.normalized(from: "Am")
        let fallback = KeySignature.normalized(from: "Pending")

        XCTAssertEqual(fSharpMinor.fifths, 3)
        XCTAssertEqual(fSharpMinor.mode, .minor)
        XCTAssertEqual(bFlatMajor.fifths, -2)
        XCTAssertEqual(bFlatMajor.mode, .major)
        XCTAssertEqual(aMinor.fifths, 0)
        XCTAssertEqual(aMinor.mode, .minor)
        XCTAssertEqual(fallback, .cMajor)
    }

    func testNotationKeySignatureAccidentalsUseTrebleStaffPositions() {
        let cMajor = KeySignature.normalized(from: "C major")
        let fMinor = KeySignature.normalized(from: "F minor")
        let fSharpMinor = KeySignature.normalized(from: "F# minor")

        XCTAssertTrue(cMajor.notationAccidentalGlyphs(for: .treble).isEmpty)
        XCTAssertEqual(
            fMinor.notationAccidentalGlyphs(for: .treble),
            [
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 4),
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 1),
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 5),
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 2)
            ]
        )
        XCTAssertEqual(
            fSharpMinor.notationAccidentalGlyphs(for: .treble),
            [
                KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 0),
                KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 3),
                KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: -1)
            ]
        )
    }

    func testNotationKeySignatureAccidentalsUseFullTrebleOrder() {
        let cSharpMajor = KeySignature.normalized(from: "C# major")
        let cFlatMajor = KeySignature.normalized(from: "Cb major")
        let cSharpMajorGlyphs = cSharpMajor.notationAccidentalGlyphs(for: .treble)
        let cFlatMajorGlyphs = cFlatMajor.notationAccidentalGlyphs(for: .treble)

        XCTAssertEqual(
            cSharpMajorGlyphs.map(\.staffPositionFromTopLine),
            [0, 3, -1, 2, 5, 1, 4]
        )
        XCTAssertEqual(
            cSharpMajorGlyphs.map(\.symbol),
            Array(repeating: "♯", count: 7)
        )
        XCTAssertEqual(
            cFlatMajorGlyphs.map(\.staffPositionFromTopLine),
            [4, 1, 5, 2, 6, 3, 7]
        )
        XCTAssertEqual(
            cFlatMajorGlyphs.map(\.symbol),
            Array(repeating: "♭", count: 7)
        )
    }

    func testProjectKeySelectionMapsDetectedKeysToToolbarValuesAndCanonicalNames() throws {
        let fSharpMinor = try XCTUnwrap(ProjectKeySelection.detected(from: "F# minor", confidence: 0.82))
        let bFlatMajor = try XCTUnwrap(ProjectKeySelection.detected(from: "Bb major", confidence: 0.76))
        let unknown = ProjectKeySelection.detected(from: "Pending", confidence: 0)

        XCTAssertEqual(fSharpMinor.tonic, .fSharpGb)
        XCTAssertEqual(fSharpMinor.mode, .minor)
        XCTAssertEqual(fSharpMinor.canonicalKeyName, "F# minor")
        XCTAssertEqual(fSharpMinor.source, .auto)
        XCTAssertEqual(try XCTUnwrap(fSharpMinor.confidence), 0.82, accuracy: 0.0001)

        XCTAssertEqual(bFlatMajor.tonic, .aSharpBb)
        XCTAssertEqual(bFlatMajor.mode, .major)
        XCTAssertEqual(bFlatMajor.canonicalKeyName, "Bb major")
        XCTAssertNil(unknown)
    }

    func testNotationAttributeDisplayShowsFullBlockForFirstVisibleMeasure() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )

        let display = NotationAttributeDisplay.display(
            for: attributes,
            previousAttributes: nil
        )

        XCTAssertTrue(display.showsClef)
        XCTAssertTrue(display.showsKeySignature)
        XCTAssertTrue(display.showsTimeSignature)
        XCTAssertFalse(display.isEmpty)
    }

    func testNotationAttributeDisplayShowsOnlyChangedTimeSignature() {
        let previous = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let current = MeasureAttributes(
            keySignature: previous.keySignature,
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: previous.clef
        )

        let display = NotationAttributeDisplay.display(
            for: current,
            previousAttributes: previous
        )

        XCTAssertFalse(display.showsClef)
        XCTAssertFalse(display.showsKeySignature)
        XCTAssertTrue(display.showsTimeSignature)
    }

    func testNotationAttributeDisplayShowsOnlyChangedKeyComponentAndNoOpForUnchangedAttributes() {
        let previous = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let keyChange = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "D major"),
            timeSignature: previous.timeSignature,
            clef: previous.clef
        )

        let keyDisplay = NotationAttributeDisplay.display(
            for: keyChange,
            previousAttributes: previous
        )
        let unchangedDisplay = NotationAttributeDisplay.display(
            for: previous,
            previousAttributes: previous
        )

        XCTAssertFalse(keyDisplay.showsClef)
        XCTAssertTrue(keyDisplay.showsKeySignature)
        XCTAssertFalse(keyDisplay.showsTimeSignature)
        XCTAssertTrue(unchangedDisplay.isEmpty)
    }

    func testNotationMeasureLayoutUsesSharedAttributeStaffInsetForZeroAccidentalKeys() {
        let cMajor = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "C major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let aMinor = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "A minor"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let fMajor = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )

        XCTAssertTrue(cMajor.keySignature.notationAccidentalGlyphs(for: cMajor.clef).isEmpty)
        XCTAssertTrue(aMinor.keySignature.notationAccidentalGlyphs(for: aMinor.clef).isEmpty)
        XCTAssertFalse(fMajor.keySignature.notationAccidentalGlyphs(for: fMajor.clef).isEmpty)
        XCTAssertEqual(
            NotationMeasureLayout.attributeStaffTopInset(for: cMajor, display: .full),
            AppTheme.Timeline.notationAttributeStaffTopInset,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureLayout.attributeStaffTopInset(for: aMinor, display: .full),
            NotationMeasureLayout.attributeStaffTopInset(for: fMajor, display: .full),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureLayout.attributeStaffTopInset(for: cMajor, display: .none),
            0,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutUsesSharedAttributeStaffInsetForPartialAttributeBlocks() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "Bb major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let partialDisplays = [
            NotationAttributeDisplay(showsClef: true, showsKeySignature: false, showsTimeSignature: false),
            NotationAttributeDisplay(showsClef: false, showsKeySignature: true, showsTimeSignature: false),
            NotationAttributeDisplay(showsClef: false, showsKeySignature: false, showsTimeSignature: true)
        ]

        for display in partialDisplays {
            XCTAssertEqual(
                NotationMeasureLayout.attributeStaffTopInset(for: attributes, display: display),
                AppTheme.Timeline.notationAttributeStaffTopInset,
                accuracy: 0.0001
            )
        }
    }

    func testNotationMeasureLayoutOffsetsAttributedMeasurePlayheadAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4),
            clef: .treble
        )
        let cellWidth: CGFloat = 148
        let display = NotationAttributeDisplay.full
        let attributeReserveWidth = NotationMeasureLayout.attributeReserveWidth(
            for: attributes,
            display: display
        )

        let attributedStart = NotationMeasureLayout.playheadX(
            measureIndex: 0,
            cellWidth: cellWidth,
            progress: 0,
            attributes: attributes,
            display: display
        )
        let attributedEnd = NotationMeasureLayout.playheadX(
            measureIndex: 0,
            cellWidth: cellWidth,
            progress: 1,
            attributes: attributes,
            display: display
        )
        let ordinaryStart = NotationMeasureLayout.playheadX(
            measureIndex: 1,
            cellWidth: cellWidth,
            progress: 0,
            attributes: attributes,
            display: .none
        )
        let contentStart = NotationMeasureLayout.contentStartX(
            measureIndex: 0,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display
        )
        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display,
            totalWidth: cellWidth * 4
        )
        let barlines = NotationMeasureLayout.barlineGeometries(for: [geometry])

        XCTAssertGreaterThan(attributedStart, AppTheme.Spacing.md)
        XCTAssertEqual(attributedStart, contentStart, accuracy: 0.0001)
        XCTAssertEqual(attributedStart, attributeReserveWidth, accuracy: 0.0001)
        XCTAssertEqual(attributedEnd, contentStart + cellWidth, accuracy: 0.0001)
        XCTAssertEqual(ordinaryStart, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentStartX, attributedStart, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentEndX, contentStart + cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentEndX - geometry.contentStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadX(geometry: geometry, progress: 1),
            geometry.contentEndX,
            accuracy: 0.0001
        )
        XCTAssertEqual(geometry.staffStartX, AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertFalse(geometry.includesRawStartBarline)
        XCTAssertTrue(geometry.contentStartsAfterCellBoundary)
        XCTAssertEqual(geometry.leadingBarlineX ?? -1, geometry.staffStartX, accuracy: 0.0001)
        XCTAssertTrue(barlines.contains { abs($0.x - geometry.staffStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometry.contentStartX) < 0.0001 })
        XCTAssertEqual(barlines.count, 2)
        XCTAssertEqual(barlines[1].x, geometry.cellEndX, accuracy: 0.0001)
        XCTAssertTrue(barlines[0].isOuterBoundary)
        XCTAssertTrue(barlines[1].isOuterBoundary)
    }

    func testNotationMeasureLayoutUsesTimeOnlyWidthAtTimeSignatureChange() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let display = NotationAttributeDisplay(
            showsClef: false,
            showsKeySignature: false,
            showsTimeSignature: true
        )
        let cellWidth: CGFloat = 148

        let blockWidth = NotationMeasureLayout.attributeBlockWidth(
            for: attributes,
            display: display,
            cellWidth: cellWidth
        )
        let contentStart = NotationMeasureLayout.contentStartX(
            measureIndex: 2,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display
        )
        let playheadStart = NotationMeasureLayout.playheadX(
            measureIndex: 2,
            cellWidth: cellWidth,
            progress: 0,
            attributes: attributes,
            display: display
        )
        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 2,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display,
            totalWidth: cellWidth * 4
        )
        let barlines = NotationMeasureLayout.barlineGeometries(for: [geometry])

        XCTAssertEqual(blockWidth, AppTheme.Timeline.notationTimeSignatureWidth, accuracy: 0.0001)
        XCTAssertEqual(contentStart, playheadStart, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffStartX, geometry.cellStartX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentStartX, contentStart, accuracy: 0.0001)
        XCTAssertTrue(geometry.includesRawStartBarline)
        XCTAssertTrue(geometry.contentStartsAfterCellBoundary)
        XCTAssertTrue(barlines.contains { abs($0.x - geometry.cellStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometry.contentStartX) < 0.0001 })
    }

    func testNotationMeasureLayoutUsesThemeClefWidthInFullAttributeReserve() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let blockWidth = NotationMeasureLayout.attributeBlockWidth(
            for: attributes,
            display: .full,
            cellWidth: AppTheme.Timeline.notationMeasureMinWidth
        )
        let reserveWidth = NotationMeasureLayout.attributeReserveWidth(
            for: attributes,
            display: .full
        )
        let expectedBlockWidth = AppTheme.Timeline.notationClefWidth
            + NotationMeasureLayout.keySignatureWidth(for: attributes)
            + AppTheme.Timeline.notationTimeSignatureWidth
            + NotationMeasureLayout.spacingWidth(forVisibleComponentCount: 3)

        XCTAssertEqual(blockWidth, expectedBlockWidth, accuracy: 0.0001)
        XCTAssertEqual(
            reserveWidth,
            AppTheme.Spacing.md + expectedBlockWidth + AppTheme.Spacing.xs,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutKeepsOrdinaryMeasureAtRawBoundary() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "C major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let cellWidth: CGFloat = 148

        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 1,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: .none,
            totalWidth: cellWidth * 4
        )

        XCTAssertEqual(geometry.cellStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffStartX, cellWidth, accuracy: 0.0001)
        XCTAssertTrue(geometry.includesRawStartBarline)
        XCTAssertFalse(geometry.contentStartsAfterCellBoundary)
    }

    func testNotationMeasureLayoutKeepsPreviousBoundaryForAttributedMiddleMeasure() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "Bb major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let cellWidth: CGFloat = 148
        let display = NotationAttributeDisplay.full
        let attributeReserveWidth = NotationMeasureLayout.attributeReserveWidth(
            for: attributes,
            display: display
        )

        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 2,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display,
            totalWidth: cellWidth * 4
        )

        XCTAssertEqual(geometry.cellStartX, cellWidth * 2, accuracy: 0.0001)
        XCTAssertGreaterThan(geometry.contentStartX, geometry.cellStartX)
        XCTAssertEqual(geometry.contentStartX, geometry.cellStartX + attributeReserveWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentEndX - geometry.contentStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.cellEndX, geometry.contentStartX + cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffStartX, geometry.cellStartX, accuracy: 0.0001)
        XCTAssertTrue(geometry.includesRawStartBarline)
        XCTAssertTrue(geometry.contentStartsAfterCellBoundary)
        XCTAssertFalse(
            NotationMeasureLayout.barlineGeometries(for: [geometry])
                .contains { abs($0.x - geometry.contentStartX) < 0.0001 }
        )
    }

    func testNotationMeasureLayoutExpandsAttributedMeasuresWithoutShrinkingBodies() {
        let fullAttributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4),
            clef: .treble
        )
        let timeOnlyAttributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let bodyWidth: CGFloat = 148
        let fullReserve = NotationMeasureLayout.attributeReserveWidth(
            for: fullAttributes,
            display: .full
        )
        let timeReserve = NotationMeasureLayout.attributeReserveWidth(
            for: timeOnlyAttributes,
            display: NotationAttributeDisplay(
                showsClef: false,
                showsKeySignature: false,
                showsTimeSignature: true
            )
        )
        let totalWidth = NotationMeasureLayout.canvasWidth(
            measureCount: 4,
            availableWidth: bodyWidth * 4,
            attributeReserveWidths: [fullReserve, 0, timeReserve, 0]
        )

        let geometries = NotationMeasureLayout.canvasGeometries(
            measureCount: 4,
            totalWidth: totalWidth,
            attributeReserveWidths: [fullReserve, 0, timeReserve, 0]
        )
        let barlines = NotationMeasureLayout.barlineGeometries(for: geometries)

        XCTAssertEqual(geometries.count, 4)
        XCTAssertEqual(totalWidth, bodyWidth * 4 + fullReserve + timeReserve, accuracy: 0.0001)
        XCTAssertEqual(geometries[0].contentStartX, fullReserve, accuracy: 0.0001)
        XCTAssertEqual(geometries[2].contentStartX, geometries[2].cellStartX + timeReserve, accuracy: 0.0001)

        for geometry in geometries {
            XCTAssertEqual(geometry.contentEndX - geometry.contentStartX, bodyWidth, accuracy: 0.0001)
        }

        XCTAssertEqual(geometries[1].cellStartX, geometries[0].cellEndX, accuracy: 0.0001)
        XCTAssertEqual(geometries[2].cellStartX, geometries[1].cellEndX, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].cellStartX, geometries[2].cellEndX, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].cellEndX, totalWidth, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].contentEndX, totalWidth, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadX(geometry: geometries[3], progress: 1),
            totalWidth,
            accuracy: 0.0001
        )
        XCTAssertLessThanOrEqual(
            NotationMeasureLayout.playheadIndicatorX(
                geometry: geometries[3],
                progress: 1,
                indicatorWidth: AppTheme.Stroke.thick
            ) + AppTheme.Stroke.thick,
            geometries[3].staffEndX + 0.0001
        )
        XCTAssertEqual(geometries[0].staffStartX, AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].staffEndX, totalWidth - AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, totalWidth - AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, geometries[3].staffEndX, accuracy: 0.0001)
        XCTAssertTrue(barlines.contains { abs($0.x - geometries[1].cellStartX) < 0.0001 })
        XCTAssertTrue(barlines.contains { abs($0.x - geometries[2].cellStartX) < 0.0001 })
        XCTAssertTrue(barlines.contains { abs($0.x - geometries[3].cellStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometries[0].contentStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometries[2].contentStartX) < 0.0001 })
    }

    func testNotationMeasureLayoutFallbackGeometryPreservesSymmetricOuterInsets() {
        let totalWidth: CGFloat = 296

        let geometries = NotationMeasureLayout.fallbackCanvasGeometries(
            measureCount: 0,
            totalWidth: totalWidth
        )
        let barlines = NotationMeasureLayout.barlineGeometries(for: geometries)

        XCTAssertEqual(geometries.count, 1)
        XCTAssertEqual(geometries[0].contentStartX, 0, accuracy: 0.0001)
        XCTAssertEqual(geometries[0].staffStartX, AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(geometries[0].staffEndX, totalWidth - AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertTrue(geometries[0].includesRawStartBarline)
        XCTAssertFalse(geometries[0].contentStartsAfterCellBoundary)
        XCTAssertEqual(geometries[0].leadingBarlineX ?? -1, geometries[0].staffStartX, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, geometries[0].staffEndX, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadX(geometry: geometries[0], progress: 0),
            geometries[0].contentStartX,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureLayout.playheadIndicatorX(
                geometry: geometries[0],
                progress: 0,
                indicatorWidth: AppTheme.Stroke.thick
            ),
            geometries[0].staffStartX,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutClampsSymmetricOuterInsetsForNarrowWidth() {
        let inset = AppTheme.Timeline.notationStaffHorizontalInset
        let totalWidth = inset * 1.5

        let geometries = NotationMeasureLayout.fallbackCanvasGeometries(
            measureCount: 1,
            totalWidth: totalWidth
        )
        let geometry = geometries[0]
        let barlines = NotationMeasureLayout.barlineGeometries(for: geometries)

        XCTAssertEqual(geometry.staffStartX, inset, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffEndX, geometry.staffStartX, accuracy: 0.0001)
        XCTAssertEqual(barlines.first?.x ?? -1, geometry.staffStartX, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, geometry.staffEndX, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadIndicatorX(
                geometry: geometry,
                progress: 1,
                indicatorWidth: AppTheme.Stroke.thick
            ),
            geometry.staffStartX,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutPositionsSlashBeatCentersForFourFour() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 10,
            staffEndX: 150
        )

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: .fourFour
        )

        XCTAssertEqual(centers.count, 4)
        XCTAssertEqual(centers[0], 10, accuracy: 0.0001)
        XCTAssertEqual(centers[1], 50, accuracy: 0.0001)
        XCTAssertEqual(centers[2], 90, accuracy: 0.0001)
        XCTAssertEqual(centers[3], 130, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutPositionsSlashBeatCentersAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "Bb major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: 148,
            attributes: attributes,
            display: .full,
            totalWidth: 592
        )

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: attributes.timeSignature
        )
        let beatSpacing = (geometry.contentEndX - geometry.contentStartX) / 3

        XCTAssertEqual(centers.count, 3)
        XCTAssertEqual(
            centers[0],
            geometry.contentStartX + AppTheme.Timeline.notationBeatAnchorInset,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[1],
            geometry.contentStartX + AppTheme.Timeline.notationBeatAnchorInset + beatSpacing,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[2],
            geometry.contentStartX + AppTheme.Timeline.notationBeatAnchorInset + beatSpacing * 2,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutPositionsSlashBeatCentersForSevenFour() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 0,
            cellEndX: 210,
            contentStartX: 0,
            contentEndX: 210,
            staffStartX: 0,
            staffEndX: 210
        )

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4)
        )

        XCTAssertEqual(centers.count, 7)
        XCTAssertEqual(centers[0], 10, accuracy: 0.0001)
        XCTAssertEqual(centers[6], 190, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutPositionsSlashBeatCentersForNonQuarterBeatUnit() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 180,
            contentStartX: 0,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 180
        )
        var sixEight = TimeSignature.fourFour
        sixEight.beatsPerBar = 6
        sixEight.beatUnit = 8

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: sixEight
        )

        XCTAssertEqual(centers.count, 6)
        XCTAssertEqual(centers[0], 10, accuracy: 0.0001)
        XCTAssertEqual(centers[1], 40, accuracy: 0.0001)
        XCTAssertEqual(centers[5], 160, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutOmitsSlashBeatCentersWhenContentIsInvalidOrTooNarrow() {
        let zeroWidthGeometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 80,
            contentStartX: 40,
            contentEndX: 40,
            staffStartX: 0,
            staffEndX: 80
        )
        let negativeWidthGeometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 80,
            contentStartX: 50,
            contentEndX: 40,
            staffStartX: 0,
            staffEndX: 80
        )
        let narrowGeometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 40,
            contentStartX: 0,
            contentEndX: 40,
            staffStartX: 0,
            staffEndX: 40
        )

        XCTAssertTrue(NotationMeasureLayout.slashBeatCenters(
            geometry: zeroWidthGeometry,
            timeSignature: .fourFour
        ).isEmpty)
        XCTAssertTrue(NotationMeasureLayout.slashBeatCenters(
            geometry: negativeWidthGeometry,
            timeSignature: .fourFour
        ).isEmpty)
        XCTAssertTrue(NotationMeasureLayout.slashBeatCenters(
            geometry: narrowGeometry,
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4)
        ).isEmpty)
    }

    func testNotationMeasureLayoutAlignsHarmonyAndSlashAnchors() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )
        let slashCenters = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: .fourFour
        )

        let firstHarmonyX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )
        let thirdHarmonyX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )

        XCTAssertEqual(firstHarmonyX, slashCenters[0], accuracy: 0.0001)
        XCTAssertEqual(thirdHarmonyX, slashCenters[2], accuracy: 0.0001)
    }

    func testNotationMeasureLayoutClampsHarmonyAnchorsInsideMeasure() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )

        let endX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: NotationMeasureLayout.quarterLength(for: .fourFour),
            timeSignature: .fourFour
        )
        let outOfRangeX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 99,
            timeSignature: .fourFour
        )

        XCTAssertEqual(endX, geometry.contentEndX, accuracy: 0.0001)
        XCTAssertEqual(outOfRangeX, geometry.contentEndX, accuracy: 0.0001)
    }

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

    func testNotationMeasureLayoutMapsAnchorXBackToProgress() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )
        let firstAnchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )
        let thirdAnchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )

        XCTAssertEqual(
            NotationMeasureLayout.notationAnchorProgress(atX: firstAnchorX, geometry: geometry),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureLayout.notationAnchorProgress(atX: thirdAnchorX, geometry: geometry),
            0.5,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutPositionsHarmonyLabelBeforeInnerBeatAnchor() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )

        let anchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )
        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )

        XCTAssertEqual(
            labelX,
            anchorX - AppTheme.Timeline.notationHarmonyAnchorLeadingOffset,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutClampsFirstHarmonyLabelToVisibleStaffStart() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: AppTheme.Timeline.notationStaffHorizontalInset,
            staffEndX: 150
        )

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )

        XCTAssertEqual(labelX, geometry.staffStartX, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutKeepsAttributedFirstHarmonyLabelAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: 148,
            attributes: attributes,
            display: .full,
            totalWidth: 592
        )

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: attributes.timeSignature
        )
        let anchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: attributes.timeSignature
        )

        XCTAssertGreaterThanOrEqual(labelX, geometry.contentStartX)
        XCTAssertEqual(
            labelX,
            anchorX - AppTheme.Timeline.notationHarmonyAnchorLeadingOffset,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutPositionsNonFirstMeasureHarmonyLabelNearContentStart() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 160,
            cellEndX: 320,
            contentStartX: 160,
            contentEndX: 320,
            staffStartX: 160,
            staffEndX: 320
        )

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )
        let anchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )

        XCTAssertGreaterThanOrEqual(labelX, geometry.contentStartX)
        XCTAssertEqual(
            labelX,
            anchorX - AppTheme.Timeline.notationHarmonyAnchorLeadingOffset,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutKeepsHarmonyLabelXBoundedForInvalidGeometry() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 40,
            contentStartX: 40,
            contentEndX: 40,
            staffStartX: 20,
            staffEndX: 40
        )

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 99,
            timeSignature: .fourFour
        )

        XCTAssertFalse(labelX.isNaN)
        XCTAssertEqual(labelX, geometry.contentStartX, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutPositionsSystemMeasureNumberAtStaffStart() {
        let cellWidth: CGFloat = 148
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "C major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let firstGeometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: .full,
            totalWidth: cellWidth * 4
        )

        let labelX = NotationMeasureLayout.systemMeasureNumberLabelX(
            geometry: firstGeometry
        )
        let labelTrailingX = NotationMeasureLayout.systemMeasureNumberLabelTrailingX(
            geometry: firstGeometry
        )
        let expectedTrailingX = firstGeometry.staffStartX + AppTheme.Spacing.sm
        let expectedX = expectedTrailingX - NotationMeasureLayout.measureNumberLabelWidth

        let staffTop: CGFloat = 32
        let labelY = NotationMeasureLayout.systemMeasureNumberLabelY(staffTop: staffTop)
        let shallowLabelY = NotationMeasureLayout.systemMeasureNumberLabelY(
            staffTop: AppTheme.Spacing.xs
        )

        XCTAssertEqual(labelTrailingX, expectedTrailingX, accuracy: 0.0001)
        XCTAssertEqual(
            labelX + NotationMeasureLayout.measureNumberLabelWidth,
            expectedTrailingX,
            accuracy: 0.0001
        )
        XCTAssertEqual(labelX, expectedX, accuracy: 0.0001)
        XCTAssertLessThan(labelX, firstGeometry.staffStartX)
        XCTAssertEqual(
            labelY,
            staffTop - NotationMeasureLayout.systemMeasureNumberStaffGap,
            accuracy: 0.0001
        )
        XCTAssertEqual(shallowLabelY, AppTheme.Spacing.xs, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutKeepsHarmonyLabelAboveStaff() {
        let defaultStaffTop: CGFloat = 32
        let lowerStaffTop: CGFloat = 60

        let defaultY = NotationMeasureLayout.harmonyLabelY(staffTop: defaultStaffTop)
        let lowerY = NotationMeasureLayout.harmonyLabelY(staffTop: lowerStaffTop)

        XCTAssertEqual(defaultY, AppTheme.Spacing.xs, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(
            defaultY + AppTheme.ControlSize.abletonNumberFieldHeight + AppTheme.Spacing.xs,
            defaultStaffTop
        )
        XCTAssertEqual(
            lowerY + AppTheme.ControlSize.abletonNumberFieldHeight + AppTheme.Spacing.xs,
            lowerStaffTop,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutKeepsRegionLabelAboveHarmonyLabel() {
        let staffTop: CGFloat = 50

        let regionY = NotationMeasureLayout.regionLabelY(staffTop: staffTop)
        let harmonyY = NotationMeasureLayout.harmonyLabelY(staffTop: staffTop)

        XCTAssertLessThan(regionY, harmonyY)
        XCTAssertLessThanOrEqual(
            regionY
                + AppTheme.Timeline.notationRegionLabelHeight
                + AppTheme.Timeline.notationRegionLabelGap,
            harmonyY + 0.0001
        )
    }

    func testNotationMeasureLayoutKeepsFirstRegionLabelAfterMeasureNumber() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 180,
            contentStartX: 0,
            contentEndX: 180,
            staffStartX: 10,
            staffEndX: 180
        )

        let x = NotationMeasureLayout.regionLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour,
            avoidsSystemMeasureNumber: true
        )
        let minimumX = NotationMeasureLayout.systemMeasureNumberLabelTrailingX(
            geometry: geometry
        ) + AppTheme.Spacing.sm

        XCTAssertGreaterThanOrEqual(x, minimumX)
    }

    func testNotationMeasureLayoutClampsRegionLabelInsideVisibleBounds() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 180,
            cellEndX: 360,
            contentStartX: 180,
            contentEndX: 360,
            staffStartX: 180,
            staffEndX: 350
        )
        let labelWidth: CGFloat = 64

        let x = NotationMeasureLayout.regionLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 99,
            timeSignature: .fourFour,
            labelWidth: labelWidth
        )

        XCTAssertGreaterThanOrEqual(x, geometry.staffStartX)
        XCTAssertLessThanOrEqual(x + labelWidth, geometry.staffEndX + 0.0001)
    }

    func testNotationMeasureLayoutPositionsHarmonyAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4),
            clef: .treble
        )
        let cellWidth: CGFloat = 148
        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: .full,
            totalWidth: cellWidth * 4
        )

        let harmonyStartX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: attributes.timeSignature
        )
        let snappedEndOffset = NotationMeasureLayout.snappedHarmonyOffset(
            7,
            timeSignature: attributes.timeSignature,
            resolution: HarmonyInputResolution(denominator: 4)
        )

        XCTAssertEqual(
            harmonyStartX,
            geometry.contentStartX + AppTheme.Timeline.notationBeatAnchorInset,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(harmonyStartX, geometry.cellStartX)
        XCTAssertEqual(snappedEndOffset, 6, accuracy: 0.0001)
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
