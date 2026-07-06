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

    func testNotationSMuFLRestSymbolsMapDurationsToCodepoints() throws {
        let whole = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 1)))
        let half = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 2)))
        let quarter = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 4)))
        let eighth = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 8)))

        XCTAssertEqual(whole, .restWhole)
        XCTAssertEqual(whole.codepoint, 0xE4E3)
        XCTAssertEqual(half, .restHalf)
        XCTAssertEqual(half.codepoint, 0xE4E4)
        XCTAssertEqual(quarter, .restQuarter)
        XCTAssertEqual(quarter.codepoint, 0xE4E5)
        XCTAssertEqual(eighth, .rest8th)
        XCTAssertEqual(eighth.codepoint, 0xE4E6)
        XCTAssertEqual(quarter.glyph.unicodeScalars.first?.value, 0xE4E5)
    }

    func testNotationRestItemFactoryUsesGreedyAllowedDurationDecomposition() {
        let segments = NotationRestItemFactory.greedySegments(startOffset: 0, remaining: 3.5)

        XCTAssertEqual(segments.map(\.displayDuration.denominator), [2, 4, 8])
        XCTAssertEqual(segments.map(\.offsetInQuarterNotes), [0, 2, 3])
        XCTAssertEqual(segments.map(\.durationInQuarterNotes), [2, 1, 0.5])
        XCTAssertEqual(segments.map(\.isTail), [false, false, false])
    }

    func testNotationRestItemFactoryUsesTimelineToleranceForMinimumDuration() {
        let tolerance = NotationMeasureTiming.timelineTolerance

        let withinTolerance = NotationRestItemFactory.greedySegments(
            startOffset: 1,
            remaining: 0.5 - tolerance / 2
        )
        let outsideTolerance = NotationRestItemFactory.greedySegments(
            startOffset: 1,
            remaining: 0.5 - tolerance * 2
        )

        XCTAssertEqual(withinTolerance.map(\.displayDuration.denominator), [8])
        XCTAssertEqual(withinTolerance.map(\.offsetInQuarterNotes), [1])
        XCTAssertTrue(outsideTolerance.isEmpty)
    }

    func testNotationRestItemFactoryLetsCallerControlIDsAndSynthesizedState() throws {
        let synthesized = NotationRestItemFactory.restItems(
            measureNumber: 2,
            measureStartTime: 4,
            startOffset: 1,
            remaining: 1,
            isSynthesized: true
        ) { segment in
            "rest-\(segment.offsetInQuarterNotes)-\(segment.displayDuration.denominator)"
        }
        let persisted = NotationRestItemFactory.restItems(
            measureNumber: 2,
            measureStartTime: 4,
            startOffset: 1,
            remaining: 1
        )

        XCTAssertEqual(synthesized.map(\.id), ["rest-1.0-4"])
        XCTAssertEqual(synthesized.map(\.isSynthesized), [true])
        XCTAssertEqual(persisted.map(\.isSynthesized), [false])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(persisted.first?.id)))
    }

    func testNotationViewportFactoryDefaultWholeRestKeepsSynthesizedFieldsAndID() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 1.5,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
                clef: .treble
            )
        )

        let item = try XCTUnwrap(NotationViewportFactory.notationItems(for: measure, from: []).first)

        XCTAssertEqual(item.id, "default-rest-1-0.0-1.5")
        XCTAssertEqual(item.kind, .rest)
        XCTAssertEqual(item.measureNumber, 1)
        XCTAssertEqual(item.measureStartTime, 0)
        XCTAssertEqual(item.offsetInQuarterNotes, 0)
        XCTAssertEqual(item.durationInQuarterNotes, 3)
        XCTAssertEqual(item.displayDuration.denominator, 1)
        XCTAssertTrue(item.isSynthesized)
    }

    func testLelandFontResourceIsBundledAndRegistered() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Leland", withExtension: "otf"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(NotationMusicFontRegistry.fontName, "Leland")
    }

    func testLelandWholeRestGlyphPathHasBounds() throws {
        let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
            for: .restWhole,
            fontSize: 32.5
        ))

        XCTAssertFalse(glyphPath.path.isEmpty)
        XCTAssertGreaterThan(glyphPath.bounds.width, 0)
        XCTAssertGreaterThan(glyphPath.bounds.height, 0)
    }

    func testWholeRestVisualCenterUsesStandardStaffPosition() {
        let y = NotationMeasureLayout.wholeRestVisualCenterY(
            staffTop: 10,
            lineSpacing: 8
        )

        XCTAssertEqual(y, 22, accuracy: 0.0001)
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

    func testMusicXMLChordParserSupportsSemanticChords() throws {
        let plain = try MusicXMLChordParser.parse("C", measureNumber: 1)
        XCTAssertEqual(plain.root, MusicXMLPitchStep(step: "C", alter: 0))
        XCTAssertEqual(plain.kindValue, "major")

        let minor = try MusicXMLChordParser.parse("Am", measureNumber: 1)
        XCTAssertEqual(minor.root, MusicXMLPitchStep(step: "A", alter: 0))
        XCTAssertEqual(minor.kindValue, "minor")

        let altered = try MusicXMLChordParser.parse("Bb13(#11)/D", measureNumber: 2)
        XCTAssertEqual(altered.root, MusicXMLPitchStep(step: "B", alter: -1))
        XCTAssertEqual(altered.kindValue, "dominant-13th")
        XCTAssertEqual(altered.bass, MusicXMLPitchStep(step: "D", alter: 0))
        XCTAssertEqual(altered.degrees, [
            MusicXMLChordDegree(value: 11, alter: 1, type: .alter)
        ])

        let halfDiminished = try MusicXMLChordParser.parse("C#m7b5", measureNumber: 3)
        XCTAssertEqual(halfDiminished.root, MusicXMLPitchStep(step: "C", alter: 1))
        XCTAssertEqual(halfDiminished.kindValue, "half-diminished")

        let added = try MusicXMLChordParser.parse("Aadd9", measureNumber: 4)
        XCTAssertEqual(added.kindValue, "major")
        XCTAssertEqual(added.degrees, [
            MusicXMLChordDegree(value: 9, alter: 0, type: .add)
        ])
    }

    func testMusicXMLChordParserRejectsUnsupportedChords() {
        XCTAssertThrowsError(try MusicXMLChordParser.parse("", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("H7", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("G7alt", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("C(foo)", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("C/G/B", measureNumber: 1))
    }

    func testMusicXMLExportIncludesMeasuresAttributesHarmonyAndRegionDirections() throws {
        let regionID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(
                duration: 8,
                markers: [timeSignatureMarker(time: 4, beatsPerBar: 3)]
            ),
            duration: 8,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "G major",
            harmonySymbols: [
                HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "Cmaj7"),
                HarmonySymbol(time: 1.5, measureNumber: 1, offsetInQuarterNotes: 3, rawText: "Bb13(#11)/D")
            ],
            notes: [
                TimecodedNote(id: regionID, kind: .region, time: 2, duration: 2, title: "Verse")
            ]
        )
        let data = try NotationExportService().export(
            NotationExportRequest(displayName: "Song", score: state),
            format: .musicXML
        )
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        let document = try XMLDocument(data: data)
        let root = try XCTUnwrap(document.rootElement())
        let rootElements = childElements(in: root)
        let childNames = rootElements.compactMap(\.name)
        let credit = try XCTUnwrap(rootElements.first { $0.name == "credit" })
        let partList = try XCTUnwrap(rootElements.first { $0.name == "part-list" })
        let scorePart = try firstXMLChild(named: "score-part", in: partList)
        let partName = try firstXMLChild(named: "part-name", in: scorePart)
        let creditWords = try firstXMLChild(named: "credit-words", in: credit)
        let part = try XCTUnwrap(rootElements.first { $0.name == "part" })
        let measures = part.elements(forName: "measure")
        let firstMeasure = try XCTUnwrap(measures.first { $0.attribute(forName: "number")?.stringValue == "1" })
        let changedTimeSignatureMeasure = try XCTUnwrap(measures.first { measure in
            guard let attributes = measure.elements(forName: "attributes").first,
                  let time = attributes.elements(forName: "time").first else {
                return false
            }
            return time.elements(forName: "beats").first?.stringValue == "3"
        })
        let firstMeasureHarmonies = firstMeasure.elements(forName: "harmony")
        let cMajorSeventhHarmony = try XCTUnwrap(firstMeasureHarmonies.first { harmony in
            harmony.elements(forName: "kind").first?.attribute(forName: "text")?.stringValue == "Cmaj7"
        })
        let alteredHarmony = try XCTUnwrap(firstMeasureHarmonies.first { harmony in
            guard let root = harmony.elements(forName: "root").first,
                  let kind = harmony.elements(forName: "kind").first else {
                return false
            }
            return root.elements(forName: "root-step").first?.stringValue == "B"
                && kind.stringValue == "dominant-13th"
        })
        let regionDirection = try XCTUnwrap(measures.lazy
            .flatMap { $0.elements(forName: "direction") }
            .first { direction in
                guard let directionType = direction.elements(forName: "direction-type").first else {
                    return false
                }
                return directionType.elements(forName: "words").first?.stringValue == "Verse"
            })
        let firstMeasureRest = try XCTUnwrap(firstMeasure.elements(forName: "note").first { note in
            note.elements(forName: "rest").first?.attribute(forName: "measure")?.stringValue == "yes"
        })

        XCTAssertTrue(xml.contains("<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">"))
        XCTAssertEqual(root.name, "score-partwise")
        XCTAssertEqual(root.attribute(forName: "version")?.stringValue, "4.0")
        XCTAssertLessThan(
            try XCTUnwrap(childNames.firstIndex(of: "credit")),
            try XCTUnwrap(childNames.firstIndex(of: "part-list"))
        )
        XCTAssertEqual(credit.attribute(forName: "page")?.stringValue, "1")
        XCTAssertEqual(credit.elements(forName: "credit-type").first?.stringValue, "title")
        XCTAssertEqual(creditWords.stringValue, "Song")
        XCTAssertEqual(creditWords.attribute(forName: "default-x")?.stringValue, "600.17")
        XCTAssertEqual(creditWords.attribute(forName: "default-y")?.stringValue, "1611.01")
        XCTAssertEqual(creditWords.attribute(forName: "justify")?.stringValue, "center")
        XCTAssertEqual(creditWords.attribute(forName: "valign")?.stringValue, "top")
        XCTAssertEqual(creditWords.attribute(forName: "font-size")?.stringValue, "22")
        XCTAssertEqual(partName.stringValue, "Song")
        XCTAssertEqual(partName.attribute(forName: "print-object")?.stringValue, "no")
        XCTAssertEqual(firstMeasure.attribute(forName: "number")?.stringValue, "1")

        let firstMeasureAttributes = try firstXMLChild(named: "attributes", in: firstMeasure)
        let firstMeasureKey = try firstXMLChild(named: "key", in: firstMeasureAttributes)
        XCTAssertEqual(try firstXMLChild(named: "fifths", in: firstMeasureKey).stringValue, "1")

        let changedTimeSignatureAttributes = try firstXMLChild(named: "attributes", in: changedTimeSignatureMeasure)
        let changedTimeSignature = try firstXMLChild(named: "time", in: changedTimeSignatureAttributes)
        XCTAssertEqual(try firstXMLChild(named: "beats", in: changedTimeSignature).stringValue, "3")

        let cMajorSeventhRoot = try firstXMLChild(named: "root", in: cMajorSeventhHarmony)
        let cMajorSeventhKind = try firstXMLChild(named: "kind", in: cMajorSeventhHarmony)
        XCTAssertEqual(try firstXMLChild(named: "root-step", in: cMajorSeventhRoot).stringValue, "C")
        XCTAssertTrue(cMajorSeventhRoot.elements(forName: "root-alter").isEmpty)
        XCTAssertEqual(cMajorSeventhKind.attribute(forName: "text")?.stringValue, "Cmaj7")
        XCTAssertEqual(cMajorSeventhKind.stringValue, "major-seventh")
        XCTAssertEqual(try firstXMLChild(named: "offset", in: cMajorSeventhHarmony).stringValue, "0")

        let alteredRoot = try firstXMLChild(named: "root", in: alteredHarmony)
        let alteredDegree = try firstXMLChild(named: "degree", in: alteredHarmony)
        let alteredBass = try firstXMLChild(named: "bass", in: alteredHarmony)
        XCTAssertEqual(try firstXMLChild(named: "root-step", in: alteredRoot).stringValue, "B")
        XCTAssertEqual(try firstXMLChild(named: "root-alter", in: alteredRoot).stringValue, "-1")
        XCTAssertEqual(try firstXMLChild(named: "degree-value", in: alteredDegree).stringValue, "11")
        XCTAssertEqual(try firstXMLChild(named: "bass-step", in: alteredBass).stringValue, "D")
        XCTAssertTrue(alteredBass.elements(forName: "bass-alter").isEmpty)
        XCTAssertEqual(try firstXMLChild(named: "offset", in: alteredHarmony).stringValue, "1440")
        try assertXMLChild(alteredHarmony, precedes: firstMeasureRest, in: firstMeasure)

        let regionDirectionType = try firstXMLChild(named: "direction-type", in: regionDirection)
        XCTAssertEqual(try firstXMLChild(named: "words", in: regionDirectionType).stringValue, "Verse")
        let rest = try firstXMLChild(named: "rest", in: firstMeasureRest)
        XCTAssertEqual(rest.attribute(forName: "measure")?.stringValue, "yes")
        XCTAssertEqual(try firstXMLChild(named: "type", in: firstMeasureRest).stringValue, "whole")
    }

    func testMusicXMLExportFailsForUnsupportedHarmony() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            harmonySymbols: [
                HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "G7alt")
            ]
        )

        XCTAssertThrowsError(
            try NotationExportService().export(
                NotationExportRequest(displayName: "Song", score: state),
                format: .musicXML
            )
        ) { error in
            XCTAssertEqual(error as? NotationExportError, .unsupportedChord(rawText: "G7alt", measureNumber: 1))
        }
    }

    func testMusicXMLExportIncludesSplitNotationRests() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: splitQuarterQuarterHalfNotationItems(),
            harmonySymbols: [
                HarmonySymbol(time: 1.5, measureNumber: 1, offsetInQuarterNotes: 3, rawText: "Fmaj7")
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let firstMeasure = try XCTUnwrap(part.elements(forName: "measure").first)
        let notes = firstMeasure.elements(forName: "note")
        let harmonies = firstMeasure.elements(forName: "harmony")
        let halfRest = try XCTUnwrap(notes.last)
        let harmony = try XCTUnwrap(harmonies.first)

        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes.map { $0.elements(forName: "duration").first?.stringValue }, ["480", "480", "960"])
        XCTAssertEqual(notes.map { $0.elements(forName: "type").first?.stringValue }, ["quarter", "quarter", "half"])
        XCTAssertEqual(try firstXMLChild(named: "offset", in: harmony).stringValue, "480")
        try assertXMLChild(harmony, precedes: halfRest, in: firstMeasure)
        XCTAssertTrue(notes.allSatisfy { note in
            note.elements(forName: "rest").first?.attribute(forName: "measure") == nil
        })
    }

    func testMusicXMLHarmonyAtNotationItemBoundaryUsesNextItemCursor() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: splitQuarterQuarterHalfNotationItems(),
            harmonySymbols: [
                HarmonySymbol(time: 1, measureNumber: 1, offsetInQuarterNotes: 2, rawText: "Dm7")
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let firstMeasure = try XCTUnwrap(part.elements(forName: "measure").first)
        let notes = firstMeasure.elements(forName: "note")
        let harmony = try XCTUnwrap(firstMeasure.elements(forName: "harmony").first)
        let thirdRest = try XCTUnwrap(notes.last)

        XCTAssertEqual(try firstXMLChild(named: "offset", in: harmony).stringValue, "0")
        try assertXMLChild(harmony, precedes: thirdRest, in: firstMeasure)
    }

    private func exportedMusicXMLDocument(for state: NotationScoreState) throws -> XMLDocument {
        let data = try NotationExportService().export(
            NotationExportRequest(displayName: "Song", score: state),
            format: .musicXML
        )
        return try XMLDocument(data: data)
    }

    private func childElements(in element: XMLElement) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }
    }

    private func assertXMLChild(
        _ firstElement: XMLElement,
        precedes secondElement: XMLElement,
        in parentElement: XMLElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let elements = childElements(in: parentElement)
        let firstIndex = try XCTUnwrap(elements.firstIndex { $0 === firstElement }, file: file, line: line)
        let secondIndex = try XCTUnwrap(elements.firstIndex { $0 === secondElement }, file: file, line: line)
        XCTAssertLessThan(firstIndex, secondIndex, file: file, line: line)
    }

    private func firstXMLChild(
        named name: String,
        in element: XMLElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XMLElement {
        try XCTUnwrap(element.elements(forName: name).first, file: file, line: line)
    }

    private func splitQuarterQuarterHalfNotationItems() -> [NotationMeasureItem] {
        [
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
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 2,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
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

    func testNotationMeasureLayoutGroupsContiguousSelectionOverlayRuns() {
        let geometries = selectionOverlayTestGeometries(count: 4, width: 100)

        let runs = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [1, 2],
            geometries: geometries
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].startMeasureIndex, 1)
        XCTAssertEqual(runs[0].endMeasureIndex, 2)
        XCTAssertEqual(runs[0].x, geometries[1].cellStartX, accuracy: 0.0001)
        XCTAssertEqual(runs[0].width, geometries[2].cellEndX - geometries[1].cellStartX, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutKeepsSingleAndNonContiguousSelectionOverlayRunsSeparate() {
        let geometries = selectionOverlayTestGeometries(count: 4, width: 100)

        let singleRun = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [1],
            geometries: geometries
        )
        let separatedRuns = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [0, 2],
            geometries: geometries
        )

        XCTAssertEqual(singleRun.map(\.startMeasureIndex), [1])
        XCTAssertEqual(singleRun.map(\.endMeasureIndex), [1])
        XCTAssertEqual(separatedRuns.map(\.startMeasureIndex), [0, 2])
        XCTAssertEqual(separatedRuns.map(\.endMeasureIndex), [0, 2])
    }

    func testNotationMeasureLayoutNormalizesSelectionOverlayRunIndices() {
        let geometries = selectionOverlayTestGeometries(count: 4, width: 100)

        let runs = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [2, 1, 1, -1, 9],
            geometries: geometries
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].startMeasureIndex, 1)
        XCTAssertEqual(runs[0].endMeasureIndex, 2)
    }

    func testNotationMeasureLayoutSelectionOverlayRunsStayWithinProvidedRowGeometry() {
        let rowGeometries = selectionOverlayTestGeometries(count: 2, width: 100)

        let runs = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [0, 1, 2],
            geometries: rowGeometries
        )
        let emptyRuns = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [],
            geometries: rowGeometries
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].startMeasureIndex, 0)
        XCTAssertEqual(runs[0].endMeasureIndex, 1)
        XCTAssertEqual(emptyRuns, [])
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
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[1],
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset + beatSpacing,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[2],
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset + beatSpacing * 2,
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

    func testNotationMeasureLayoutCentersSingleFullMeasureWholeRest() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let item = NotationMeasureItem(
            id: "whole-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 3,
            displayDuration: NotationDuration(denominator: 1)
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 1.5,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
                clef: .treble
            ),
            notationItems: [item]
        )

        let x = NotationMeasureLayout.notationItemX(
            geometry: geometry,
            measure: measure,
            item: item
        )

        XCTAssertEqual(x, 100, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutDoesNotCenterNonFullMeasureWholeRestCases() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let partialItem = NotationMeasureItem(
            id: "partial",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 1)
        )
        let offsetItem = NotationMeasureItem(
            id: "offset",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1)
        )
        let quarterItem = NotationMeasureItem(
            id: "quarter",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )

        for item in [partialItem, offsetItem, quarterItem] {
            let measure = ScoreMeasure(
                number: 1,
                startTime: 0,
                endTime: 2,
                attributes: .defaultTreble,
                notationItems: [item]
            )
            let expectedX = NotationMeasureLayout.harmonyX(
                geometry: geometry,
                offsetInQuarterNotes: item.offsetInQuarterNotes,
                timeSignature: measure.attributes.timeSignature
            )

            XCTAssertEqual(
                NotationMeasureLayout.notationItemX(
                    geometry: geometry,
                    measure: measure,
                    item: item
                ),
                expectedX,
                accuracy: 0.0001
            )
        }

        let firstSplitItem = NotationMeasureItem(
            id: "split-a",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 1)
        )
        let secondSplitItem = NotationMeasureItem(
            id: "split-b",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        let splitMeasure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [firstSplitItem, secondSplitItem]
        )

        XCTAssertEqual(
            NotationMeasureLayout.notationItemX(
                geometry: geometry,
                measure: splitMeasure,
                item: firstSplitItem
            ),
            NotationMeasureLayout.harmonyX(
                geometry: geometry,
                offsetInQuarterNotes: firstSplitItem.offsetInQuarterNotes,
                timeSignature: splitMeasure.attributes.timeSignature
            ),
            accuracy: 0.0001
        )
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

    func testNotationTrackLayoutItemsBuildsMeasureItemsFromPureInputs() throws {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 520,
            contentStartX: 0,
            contentEndX: 520,
            staffStartX: 20,
            staffEndX: 520
        )
        let firstRegionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondRegionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let harmonyID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let notationItem = NotationMeasureItem(
            id: "quarter-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let harmony = HarmonySymbol(
            id: harmonyID,
            time: 1,
            measureNumber: 1,
            offsetInQuarterNotes: 2,
            rawText: "G7"
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [notationItem],
            harmonies: [harmony],
            regionLabels: [
                NotationRegionLabel(
                    id: firstRegionID,
                    time: 0,
                    measureNumber: 1,
                    offsetInQuarterNotes: 0,
                    title: "Intro"
                ),
                NotationRegionLabel(
                    id: secondRegionID,
                    time: 0.25,
                    measureNumber: 1,
                    offsetInQuarterNotes: 0,
                    title: "Verse"
                )
            ]
        )

        let regionItems = NotationTrackLayoutItems.regionLabels(
            visibleMeasures: [measure],
            geometries: [geometry]
        )
        let harmonyItems = NotationTrackLayoutItems.harmonies(
            visibleMeasures: [measure],
            geometries: [geometry]
        )
        let notationItems = NotationTrackLayoutItems.notationItems(
            visibleMeasures: [measure],
            geometries: [geometry]
        )

        XCTAssertEqual(regionItems.map(\.label.id), [firstRegionID, secondRegionID])
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(regionItems.first).x,
            NotationMeasureLayout.systemMeasureNumberLabelTrailingX(geometry: geometry)
                + AppTheme.Spacing.sm
        )
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(regionItems.last).x,
            try XCTUnwrap(regionItems.first).x
                + AppTheme.Timeline.notationRegionLabelMaxWidth
                + AppTheme.Timeline.notationRegionLabelGap
                - 0.0001
        )

        let harmonyItem = try XCTUnwrap(harmonyItems.first)
        XCTAssertEqual(harmonyItem.symbol, harmony)
        XCTAssertEqual(
            harmonyItem.x,
            NotationMeasureLayout.harmonyLabelX(
                geometry: geometry,
                offsetInQuarterNotes: harmony.offsetInQuarterNotes,
                timeSignature: measure.attributes.timeSignature
            ),
            accuracy: 0.0001
        )

        let layoutNotationItem = try XCTUnwrap(notationItems.first)
        XCTAssertEqual(layoutNotationItem.notationItem, notationItem)
        XCTAssertTrue(layoutNotationItem.selection.matches(measure, item: notationItem))
        XCTAssertEqual(
            layoutNotationItem.x,
            NotationMeasureLayout.notationItemX(
                geometry: geometry,
                measure: measure,
                item: notationItem
            ),
            accuracy: 0.0001
        )
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

        XCTAssertEqual(
            harmonyStartX,
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(harmonyStartX, geometry.cellStartX)
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

    private func selectionOverlayTestGeometries(
        count: Int,
        width: CGFloat
    ) -> [NotationMeasureCanvasGeometry] {
        (0..<count).map { index in
            let startX = CGFloat(index) * width
            return NotationMeasureCanvasGeometry(
                measureIndex: index,
                cellStartX: startX,
                cellEndX: startX + width,
                contentStartX: startX,
                contentEndX: startX + width,
                staffStartX: startX,
                staffEndX: startX + width
            )
        }
    }

}
