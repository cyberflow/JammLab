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

    func testCachedNotationContentMatchesDirectViewportState() {
        let tempoMap = fourFourTempoMap(duration: 120)
        let harmony = HarmonySymbol(time: 8, measureNumber: 5, offsetInQuarterNotes: 0, rawText: "Cmaj7")
        let region = TimecodedNote(kind: .region, time: 6, duration: 8, title: "Verse")
        let factory = NotationViewportFactory()
        let content = factory.scoreContent(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            harmonySymbols: [harmony],
            notes: [region]
        )

        let direct = factory.viewportState(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            currentTime: 8.1,
            playbackMarkerTime: 0,
            isPlaying: true,
            keyName: "C major",
            visibleMeasureCount: 8,
            harmonySymbols: [harmony],
            notes: [region]
        )
        let cached = factory.viewportState(
            content: content,
            duration: tempoMap.duration,
            currentTime: 8.1,
            playbackMarkerTime: 0,
            isPlaying: true,
            visibleMeasureCount: 8
        )

        XCTAssertEqual(cached, direct)
    }

    func testNotationProjectionCacheReusesEquivalentInputs() {
        let tempoMap = fourFourTempoMap(duration: 120)
        let cache = NotationProjectionCache()

        let first = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            notationItems: [],
            harmonySymbols: [],
            notes: []
        )
        let second = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            notationItems: [],
            harmonySymbols: [],
            notes: []
        )

        XCTAssertEqual(second, first)
        XCTAssertTrue(second.isReady)
        XCTAssertEqual(cache.cachedScopeCount, 1)
        XCTAssertEqual(cache.cacheMissCount, 1)
    }

    func testNotationProjectionCacheKeepsPartScopesAndGlobalRegionsIndependent() throws {
        let tempoMap = fourFourTempoMap(duration: 8)
        let cache = NotationProjectionCache()
        let regionID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let harmony = HarmonySymbol(
            time: 0,
            measureNumber: 1,
            offsetInQuarterNotes: 0,
            rawText: "C"
        )

        let main = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            partID: .main,
            includesHarmonies: true,
            notationItems: [],
            harmonySymbols: [harmony],
            notes: [TimecodedNote(id: regionID, kind: .region, time: 0.5, duration: 2, title: "Intro")]
        )
        let bass = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            partID: .stem(.bass),
            includesHarmonies: false,
            notationItems: [],
            harmonySymbols: [harmony],
            notes: [TimecodedNote(id: regionID, kind: .region, time: 0.5, duration: 2, title: "Intro")]
        )
        let mainAgain = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            partID: .main,
            includesHarmonies: true,
            notationItems: [],
            harmonySymbols: [harmony],
            notes: [TimecodedNote(id: regionID, kind: .region, time: 0.5, duration: 2, title: "Intro")]
        )
        let mainOnlyItem = NotationMeasureItem(
            id: "main-note",
            partID: .main,
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let bassWithUnrelatedChanges = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            partID: .stem(.bass),
            includesHarmonies: false,
            notationItems: [mainOnlyItem],
            harmonySymbols: [
                HarmonySymbol(time: 1, measureNumber: 1, offsetInQuarterNotes: 2, rawText: "G7")
            ],
            notes: [
                TimecodedNote(id: regionID, kind: .region, time: 0.5, duration: 2, title: "Intro"),
                TimecodedNote(kind: .marker, time: 1, title: "Marker")
            ]
        )

        XCTAssertEqual(cache.cachedScopeCount, 2)
        XCTAssertEqual(cache.cacheMissCount, 2)
        XCTAssertEqual(mainAgain, main)
        XCTAssertEqual(bassWithUnrelatedChanges, bass)
        XCTAssertEqual(main.measures.flatMap(\.harmonies).map(\.id), [harmony.id])
        XCTAssertTrue(bass.measures.flatMap(\.harmonies).isEmpty)
        XCTAssertEqual(main.measures.flatMap(\.regionLabels).map(\.id), [regionID])
        XCTAssertEqual(bass.measures.flatMap(\.regionLabels).map(\.id), [regionID])

        let bassItem = NotationMeasureItem(
            id: "bass-note",
            partID: .stem(.bass),
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 2),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        _ = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            partID: .stem(.bass),
            includesHarmonies: false,
            notationItems: [bassItem],
            harmonySymbols: [],
            notes: [TimecodedNote(id: regionID, kind: .region, time: 0.5, duration: 2, title: "Intro")]
        )
        XCTAssertEqual(cache.cacheMissCount, 3)

        _ = cache.content(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            keyName: "C major",
            partID: .stem(.bass),
            includesHarmonies: false,
            notationItems: [bassItem],
            harmonySymbols: [],
            notes: [TimecodedNote(id: regionID, kind: .region, time: 0.5, duration: 2, title: "Renamed Intro")]
        )
        XCTAssertEqual(cache.cacheMissCount, 4)

        cache.invalidate()
        XCTAssertEqual(cache.cachedScopeCount, 0)
        XCTAssertEqual(cache.cacheMissCount, 0)
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

}
