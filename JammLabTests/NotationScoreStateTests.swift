import XCTest
@testable import JammLab

final class NotationScoreStateTests: XCTestCase {
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

    func testPolyphonicProjectionPreservesOverlapsAndOnlyRestsInGlobalSilence() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 2),
            duration: 2,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                note(id: "long", pitch: .c, offset: 0, duration: 2),
                note(id: "overlap", pitch: .e, offset: 1, duration: 2),
                note(id: "same-pitch-overlap", pitch: .c, offset: 1.5, duration: 1)
            ]
        )

        let measure = try XCTUnwrap(state.measures.first)
        let notes = measure.notationItems.filter { $0.kind == .note }
        let rests = measure.notationItems.filter { $0.kind == .rest }

        XCTAssertEqual(notes.map(\.id), ["long", "overlap", "same-pitch-overlap"])
        XCTAssertEqual(notes.map(\.offsetInQuarterNotes), [0, 1, 1.5])
        XCTAssertEqual(notes.map(\.durationInQuarterNotes), [2, 2, 1])
        XCTAssertEqual(rests.count, 1)
        XCTAssertEqual(rests[0].offsetInQuarterNotes, 3, accuracy: 0.0001)
        XCTAssertEqual(rests[0].durationInQuarterNotes, 1, accuracy: 0.0001)
    }

    func testPolyphonicProjectionCreatesOneRestAfterAChord() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 2),
            duration: 2,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                note(id: "c", pitch: .c, offset: 0, duration: 1),
                note(id: "e", pitch: .e, offset: 0, duration: 1),
                NotationMeasureItem(
                    id: "stale-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0.5,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )

        let items = try XCTUnwrap(state.measures.first).notationItems
        XCTAssertEqual(items.filter { $0.kind == .note }.count, 2)
        XCTAssertFalse(items.contains { $0.id == "stale-rest" })
        XCTAssertTrue(items.filter { $0.kind == .rest }.allSatisfy {
            $0.offsetInQuarterNotes >= 1 - NotationMeasureTiming.timelineTolerance
        })
    }

    private func fourFourTempoMap(
        duration: TimeInterval,
        markers: [TimecodedNote] = []
    ) -> TempoMap {
        TempoMap(
            baseSettings: BeatGridSettings(
                bpm: 120,
                firstBeatTime: 0,
                timeSignature: .fourFour
            ),
            markers: markers,
            duration: duration
        )
    }

    private func timeSignatureMarker(time: TimeInterval, beatsPerBar: Int) -> TimecodedNote {
        TimecodedNote(
            time: time,
            title: "\(beatsPerBar)/4",
            metadata: TempoTimeSignatureMarkerPayload(
                beatsPerBar: beatsPerBar,
                setsNewFirstBeat: false
            ).metadata
        )
    }

    private func note(
        id: String,
        pitch step: NotationPitchStep,
        offset: Double,
        duration: Double
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: NotationPitch(step: step, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: duration,
            displayDuration: NotationDuration(denominator: duration >= 2 ? 2 : 4)
        )
    }
}
