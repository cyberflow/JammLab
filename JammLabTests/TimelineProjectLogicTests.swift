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

    func testProjectStateNormalizerClampsInvalidValues() throws {
        let region = TimecodedNote(kind: .region, time: -5, duration: 100, title: "", color: .regionPlum)
        let marker = TimecodedNote(time: 999, title: "")
        let notes = ProjectStateNormalizer.normalizedNotes([region, marker], duration: 12)

        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].time, 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(notes[0].duration), 12, accuracy: 0.0001)
        XCTAssertEqual(notes[0].title, "Region")
        XCTAssertEqual(notes[1].time, 12, accuracy: 0.0001)
        XCTAssertEqual(notes[1].title, "Marker")

        let loop = ProjectStateNormalizer.normalizedLoopRegion(start: 11.9, end: 11.95, duration: 12, minimumLength: 1)
        XCTAssertEqual(loop.start, 11, accuracy: 0.0001)
        XCTAssertEqual(loop.end, 12, accuracy: 0.0001)
    }

    func testProjectStateNormalizerClampsAndSortsHarmonySymbols() throws {
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

        let symbols = ProjectStateNormalizer.normalizedHarmonySymbols([
            HarmonySymbol(
                id: laterID,
                time: 999,
                measureNumber: 0,
                offsetInQuarterNotes: .nan,
                rawText: "G7 alt"
            ),
            HarmonySymbol(
                id: earlierID,
                time: -5,
                measureNumber: -3,
                offsetInQuarterNotes: 1.5,
                rawText: " Cmaj7 "
            )
        ], duration: 12)

        XCTAssertEqual(symbols.map(\.id), [earlierID, laterID])
        XCTAssertEqual(symbols[0].time, 0, accuracy: 0.0001)
        XCTAssertEqual(symbols[0].measureNumber, 1)
        XCTAssertEqual(symbols[0].offsetInQuarterNotes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(symbols[0].rawText, " Cmaj7 ")
        XCTAssertEqual(symbols[1].time, 12, accuracy: 0.0001)
        XCTAssertEqual(symbols[1].measureNumber, 1)
        XCTAssertEqual(symbols[1].offsetInQuarterNotes, 0, accuracy: 0.0001)
        XCTAssertEqual(symbols[1].rawText, "G7 alt")
    }

    func testProjectStateNormalizerUsesSliderDefaultsForPlaybackControls() {
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPlaybackRate(0),
            AppSliderDefaults.minimumPlaybackRate,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPlaybackRate(2),
            AppSliderDefaults.maximumPlaybackRate,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPlaybackRate(.nan),
            AppSliderDefaults.playbackRate,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPitchShift(-24),
            AppSliderDefaults.minimumPitchShiftSemitones,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPitchShift(24),
            AppSliderDefaults.maximumPitchShiftSemitones,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProjectStateNormalizer.normalizedPitchShift(.nan),
            AppSliderDefaults.pitchShiftSemitones,
            accuracy: 0.0001
        )
    }
}
