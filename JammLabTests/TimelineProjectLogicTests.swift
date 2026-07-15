import XCTest
@testable import JammLab

final class TimelineProjectLogicTests: XCTestCase {
    func testLoopRegionRespectsCustomMinimumLength() {
        let region = LoopRegion(start: 2, end: 5)

        let movedStart = region.movingStart(to: 4.5, trackDuration: 10, minimumLength: 2)
        XCTAssertEqual(movedStart.start, 3, accuracy: 0.0001)
        XCTAssertEqual(movedStart.end, 5, accuracy: 0.0001)

        let movedEnd = region.movingEnd(to: 2.5, trackDuration: 10, minimumLength: 2)
        XCTAssertEqual(movedEnd.start, 2, accuracy: 0.0001)
        XCTAssertEqual(movedEnd.end, 4, accuracy: 0.0001)

        let shifted = region.offset(by: 20, trackDuration: 10, minimumLength: 2)
        XCTAssertEqual(shifted.start, 7, accuracy: 0.0001)
        XCTAssertEqual(shifted.end, 10, accuracy: 0.0001)
    }

    func testRegionNotePersistsDurationAndComputesEnd() throws {
        let note = TimecodedNote(kind: .region, time: 12.3, duration: 4.5, title: "Chorus", color: .regionBlue)
        let data = try JSONEncoder().encode(note)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(try XCTUnwrap(object["time"] as? Double), 12.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(object["duration"] as? Double), 4.5, accuracy: 0.0001)
        XCTAssertNil(object["endTime"])

        let decoded = try JSONDecoder().decode(TimecodedNote.self, from: data)
        XCTAssertEqual(decoded.regionEndTime, 16.8, accuracy: 0.0001)
    }

    func testLegacyRegionEndTimeDecodesToDuration() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "kind": "loop",
          "time": 3.0,
          "endTime": 8.25,
          "title": "Legacy Loop",
          "color": "green"
        }
        """

        let decoded = try JSONDecoder().decode(TimecodedNote.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.isRegion)
        XCTAssertEqual(try XCTUnwrap(decoded.duration), 5.25, accuracy: 0.0001)
        XCTAssertEqual(decoded.regionEndTime, 8.25, accuracy: 0.0001)
        XCTAssertEqual(decoded.color, .regionDefault)
    }

    func testProjectDecodeDefaultsMissingHarmonySymbolsToEmptyArray() throws {
        let project = JammLabProject(
            audioBookmarkData: Data([1, 2, 3]),
            audioDisplayName: "song.wav",
            audioDuration: 12,
            notes: [],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )
        let data = try JSONEncoder().encode(project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "harmonySymbols")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(JammLabProject.self, from: legacyData)

        XCTAssertTrue(decoded.harmonySymbols.isEmpty)
    }

    func testProjectPersistsHarmonySymbolsAsRawText() throws {
        let symbol = HarmonySymbol(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            time: 1.25,
            measureNumber: 1,
            offsetInQuarterNotes: 2.5,
            rawText: "Bb13(#11)/D"
        )
        let project = JammLabProject(
            audioBookmarkData: Data([1, 2, 3]),
            audioDisplayName: "song.wav",
            audioDuration: 12,
            notes: [],
            harmonySymbols: [symbol],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )

        let decoded = try JSONDecoder().decode(JammLabProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded.harmonySymbols, [symbol])
    }

    func testProjectPersistsNotationPartState() throws {
        let notationItem = NotationMeasureItem(
            id: "bass-note",
            partID: .stem(.bass),
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 2),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 0.25,
            displayDuration: NotationDuration(denominator: 16)
        )
        let notationRest = NotationMeasureItem(
            id: "main-rest",
            kind: .rest,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0.25,
            durationInQuarterNotes: 0.25,
            displayDuration: NotationDuration(denominator: 16)
        )
        let project = JammLabProject(
            audioBookmarkData: Data([1, 2, 3]),
            audioDisplayName: "song.wav",
            audioDuration: 12,
            notes: [],
            notationItems: [notationItem, notationRest],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: 1,
            pitchShiftSemitones: 0,
            stemNotationTrackCollapsed: [.bass: false, .drums: true],
            visibleNotationPartIDs: [.main, .stem(.bass), .stem(.drums)]
        )

        let decoded = try JSONDecoder().decode(
            JammLabProject.self,
            from: JSONEncoder().encode(project)
        )

        XCTAssertEqual(decoded.notationItems.first?.partID, .stem(.bass))
        XCTAssertEqual(decoded.notationItems.map(\.kind), [.note, .rest])
        XCTAssertEqual(decoded.notationItems.map(\.displayDuration.denominator), [16, 16])
        XCTAssertEqual(decoded.notationItems.map(\.durationInQuarterNotes), [0.25, 0.25])
        XCTAssertEqual(decoded.stemNotationTrackCollapsed, [.bass: false, .drums: true])
        XCTAssertEqual(decoded.visibleNotationPartIDs, [.main, .stem(.bass), .stem(.drums)])
    }

    func testProjectDefaultsMissingNotationPartState() throws {
        let project = JammLabProject(
            audioBookmarkData: Data([1, 2, 3]),
            audioDisplayName: "song.wav",
            audioDuration: 12,
            notes: [],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: 1,
            pitchShiftSemitones: 0
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any]
        )
        object.removeValue(forKey: "stemNotationTrackCollapsed")
        object.removeValue(forKey: "visibleNotationPartIDs")

        let decoded = try JSONDecoder().decode(
            JammLabProject.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(decoded.stemNotationTrackCollapsed.isEmpty)
        XCTAssertEqual(decoded.visibleNotationPartIDs, [.main])
    }

}
