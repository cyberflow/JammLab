import XCTest
@testable import JammLab

final class NotationAttributeDisplayTests: XCTestCase {
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
}
