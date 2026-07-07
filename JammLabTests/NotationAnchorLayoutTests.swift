import XCTest
@testable import JammLab

final class NotationAnchorLayoutTests: XCTestCase {
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
}
