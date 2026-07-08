import XCTest
@testable import JammLab

final class ProjectStateNormalizerTests: XCTestCase {
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
