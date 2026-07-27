import XCTest
@testable import JammLab

final class NotationSlashBeatLayoutTests: XCTestCase {
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
        let beatSpacing = (geometry.rhythmicEndX - geometry.rhythmicStartX) / 4

        XCTAssertEqual(centers.count, 4)
        XCTAssertEqual(centers[0], geometry.rhythmicStartX, accuracy: 0.0001)
        XCTAssertEqual(
            centers[1],
            geometry.rhythmicStartX + beatSpacing,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[2],
            geometry.rhythmicStartX + beatSpacing * 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[3],
            geometry.rhythmicStartX + beatSpacing * 3,
            accuracy: 0.0001
        )
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
        let beatSpacing = (geometry.rhythmicEndX - geometry.rhythmicStartX) / 3

        XCTAssertEqual(centers.count, 3)
        XCTAssertEqual(
            centers[0],
            geometry.rhythmicStartX,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[1],
            geometry.rhythmicStartX + beatSpacing,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[2],
            geometry.rhythmicStartX + beatSpacing * 2,
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
        XCTAssertEqual(centers[0], geometry.rhythmicStartX, accuracy: 0.0001)
        XCTAssertEqual(
            centers[6],
            geometry.rhythmicStartX
                + (geometry.rhythmicEndX - geometry.rhythmicStartX) * 6 / 7,
            accuracy: 0.0001
        )
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
        XCTAssertEqual(centers[0], geometry.rhythmicStartX, accuracy: 0.0001)
        XCTAssertEqual(
            centers[1],
            geometry.rhythmicStartX
                + (geometry.rhythmicEndX - geometry.rhythmicStartX) / 6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[5],
            geometry.rhythmicStartX
                + (geometry.rhythmicEndX - geometry.rhythmicStartX) * 5 / 6,
            accuracy: 0.0001
        )
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
}
