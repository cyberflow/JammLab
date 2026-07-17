import XCTest
@testable import JammLab

final class NotationDurationEditorTests: XCTestCase {
    func testRecomposesSelectedRestAndRemainingMeasure() throws {
        let measure = makeMeasure()
        let selectedRest = try XCTUnwrap(measure.notationItems.first)

        let replacement = try XCTUnwrap(NotationDurationEditor.replacement(
            in: measure,
            selectedItem: selectedRest,
            selectedDuration: NotationDuration(denominator: 4)
        ))
        let items = replacement.items

        XCTAssertEqual(items.map(\.displayDuration.denominator), [4, 2, 4])
        XCTAssertEqual(items.map(\.offsetInQuarterNotes), [0, 1, 3])
        XCTAssertEqual(items.map(\.durationInQuarterNotes), [1, 2, 1])
        XCTAssertEqual(items.first?.id, selectedRest.id)
    }

    func testExpandingNoteConsumesOnlyContiguousRestAndPreservesLaterNote() throws {
        let selectedNote = NotationMeasureItem(
            id: "selected-note",
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let followingRest = NotationMeasureItem(
            id: "following-rest",
            kind: .rest,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let laterNote = NotationMeasureItem(
            id: "later-note",
            kind: .note,
            pitch: NotationPitch(step: .g, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        var measure = makeMeasure()
        measure.notationItems = [selectedNote, followingRest, laterNote]

        let replacement = try XCTUnwrap(NotationDurationEditor.replacement(
            in: measure,
            selectedItem: selectedNote,
            selectedDuration: NotationDuration(denominator: 4, isDotted: true)
        ))
        let items = replacement.items

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first?.id, "selected-note")
        XCTAssertEqual(items.first?.pitch, selectedNote.pitch)
        XCTAssertEqual(items.first?.durationInQuarterNotes, 1.5)
        XCTAssertEqual(items[1].kind, .rest)
        XCTAssertEqual(items[1].durationInQuarterNotes, 0.5)
        XCTAssertEqual(items.last, laterNote)
    }

    func testDottedSixteenthUsesThirtySecondRestToReachNextBeatBoundary() throws {
        var measure = makeMeasure()
        let selectedRest = NotationMeasureItem(
            id: "selected-rest",
            kind: .rest,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        measure.notationItems = [selectedRest]

        let replacement = try XCTUnwrap(NotationDurationEditor.replacement(
            in: measure,
            selectedItem: selectedRest,
            selectedDuration: NotationDuration(denominator: 16, isDotted: true)
        ))
        let items = replacement.items

        XCTAssertEqual(items.map(\.displayDuration.denominator), [16, 8, 32])
        XCTAssertEqual(items.map(\.durationInQuarterNotes), [0.375, 0.5, 0.125])
        XCTAssertTrue(items.first?.displayDuration.isDotted == true)
        XCTAssertTrue(items.dropFirst().allSatisfy { !$0.displayDuration.isDotted })
    }

    func testRejectsDottedExpansionWhenNextItemIsNote() {
        var measure = makeMeasure()
        let note = NotationMeasureItem(
            id: "selected-note",
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 4),
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let trailingNote = NotationMeasureItem(
            id: "trailing-note",
            kind: .note,
            pitch: NotationPitch(step: .g, octave: 4),
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        measure.notationItems = [note, trailingNote]

        let replacement = NotationDurationEditor.replacement(
            in: measure,
            selectedItem: note,
            selectedDuration: NotationDuration(denominator: 4, isDotted: true)
        )

        XCTAssertNil(replacement)
    }

    func testReplacementReturnsExactSelectedItemWhenPrefixIsPreserved() throws {
        let prefixNote = NotationMeasureItem(
            id: "prefix-note",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let selectedRest = NotationMeasureItem(
            id: "selected-rest",
            kind: .rest,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let followingRest = NotationMeasureItem(
            id: "following-rest",
            kind: .rest,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        var measure = makeMeasure()
        measure.notationItems = [followingRest, selectedRest, prefixNote]

        let replacement = try XCTUnwrap(NotationDurationEditor.replacement(
            in: measure,
            selectedItem: selectedRest,
            selectedDuration: NotationDuration(denominator: 4, isDotted: true)
        ))

        XCTAssertEqual(replacement.items.first, prefixNote)
        XCTAssertEqual(replacement.items[1], replacement.selectedItem)
        XCTAssertEqual(replacement.selectedItem.id, selectedRest.id)
        XCTAssertEqual(replacement.selectedItem.durationInQuarterNotes, 1.5)
    }

    func testMaterializesSynthesizedRestWhenDurationChanges() throws {
        var measure = makeMeasure()
        measure.notationItems[0].isSynthesized = true
        let selectedRest = measure.notationItems[0]

        let replacement = try XCTUnwrap(NotationDurationEditor.replacement(
            in: measure,
            selectedItem: selectedRest,
            selectedDuration: NotationDuration(denominator: 2, isDotted: true)
        ))

        XCTAssertNotEqual(replacement.selectedItem.id, selectedRest.id)
        XCTAssertFalse(replacement.selectedItem.isSynthesized)
        XCTAssertEqual(replacement.selectedItem.durationInQuarterNotes, 3)
        XCTAssertEqual(replacement.items.first, replacement.selectedItem)
    }

    private func makeMeasure() -> ScoreMeasure {
        let attributes = MeasureAttributes(
            keySignature: .cMajor,
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            clef: .treble
        )
        let rest = NotationMeasureItem(
            kind: .rest,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1)
        )
        return ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: attributes,
            notationItems: [rest]
        )
    }
}
