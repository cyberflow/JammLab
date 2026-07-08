import XCTest
@testable import JammLab

final class NotationAttributeStaffInsetTests: XCTestCase {
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
}
