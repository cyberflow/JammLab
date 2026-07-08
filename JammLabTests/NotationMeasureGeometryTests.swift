import XCTest
@testable import JammLab

final class NotationMeasureGeometryTests: XCTestCase {
    func testNotationMeasureLayoutKeepsOrdinaryMeasureAtRawBoundary() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "C major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let cellWidth: CGFloat = 148

        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 1,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: .none,
            totalWidth: cellWidth * 4
        )

        XCTAssertEqual(geometry.cellStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffStartX, cellWidth, accuracy: 0.0001)
        XCTAssertTrue(geometry.includesRawStartBarline)
        XCTAssertFalse(geometry.contentStartsAfterCellBoundary)
    }

    func testNotationMeasureLayoutKeepsPreviousBoundaryForAttributedMiddleMeasure() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "Bb major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let cellWidth: CGFloat = 148
        let display = NotationAttributeDisplay.full
        let attributeReserveWidth = NotationMeasureLayout.attributeReserveWidth(
            for: attributes,
            display: display
        )

        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 2,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display,
            totalWidth: cellWidth * 4
        )

        XCTAssertEqual(geometry.cellStartX, cellWidth * 2, accuracy: 0.0001)
        XCTAssertGreaterThan(geometry.contentStartX, geometry.cellStartX)
        XCTAssertEqual(geometry.contentStartX, geometry.cellStartX + attributeReserveWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentEndX - geometry.contentStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.cellEndX, geometry.contentStartX + cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffStartX, geometry.cellStartX, accuracy: 0.0001)
        XCTAssertTrue(geometry.includesRawStartBarline)
        XCTAssertTrue(geometry.contentStartsAfterCellBoundary)
        XCTAssertFalse(
            NotationMeasureLayout.barlineGeometries(for: [geometry])
                .contains { abs($0.x - geometry.contentStartX) < 0.0001 }
        )
    }

    func testNotationMeasureLayoutExpandsAttributedMeasuresWithoutShrinkingBodies() {
        let fullAttributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4),
            clef: .treble
        )
        let timeOnlyAttributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let bodyWidth: CGFloat = 148
        let fullReserve = NotationMeasureLayout.attributeReserveWidth(
            for: fullAttributes,
            display: .full
        )
        let timeReserve = NotationMeasureLayout.attributeReserveWidth(
            for: timeOnlyAttributes,
            display: NotationAttributeDisplay(
                showsClef: false,
                showsKeySignature: false,
                showsTimeSignature: true
            )
        )
        let totalWidth = NotationMeasureLayout.canvasWidth(
            measureCount: 4,
            availableWidth: bodyWidth * 4,
            attributeReserveWidths: [fullReserve, 0, timeReserve, 0]
        )

        let geometries = NotationMeasureLayout.canvasGeometries(
            measureCount: 4,
            totalWidth: totalWidth,
            attributeReserveWidths: [fullReserve, 0, timeReserve, 0]
        )
        let barlines = NotationMeasureLayout.barlineGeometries(for: geometries)

        XCTAssertEqual(geometries.count, 4)
        XCTAssertEqual(totalWidth, bodyWidth * 4 + fullReserve + timeReserve, accuracy: 0.0001)
        XCTAssertEqual(geometries[0].contentStartX, fullReserve, accuracy: 0.0001)
        XCTAssertEqual(geometries[2].contentStartX, geometries[2].cellStartX + timeReserve, accuracy: 0.0001)

        for geometry in geometries {
            XCTAssertEqual(geometry.contentEndX - geometry.contentStartX, bodyWidth, accuracy: 0.0001)
        }

        XCTAssertEqual(geometries[1].cellStartX, geometries[0].cellEndX, accuracy: 0.0001)
        XCTAssertEqual(geometries[2].cellStartX, geometries[1].cellEndX, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].cellStartX, geometries[2].cellEndX, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].cellEndX, totalWidth, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].contentEndX, totalWidth, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadX(geometry: geometries[3], progress: 1),
            totalWidth,
            accuracy: 0.0001
        )
        XCTAssertLessThanOrEqual(
            NotationMeasureLayout.playheadIndicatorX(
                geometry: geometries[3],
                progress: 1,
                indicatorWidth: AppTheme.Stroke.thick
            ) + AppTheme.Stroke.thick,
            geometries[3].staffEndX + 0.0001
        )
        XCTAssertEqual(geometries[0].staffStartX, AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(geometries[3].staffEndX, totalWidth - AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, totalWidth - AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, geometries[3].staffEndX, accuracy: 0.0001)
        XCTAssertTrue(barlines.contains { abs($0.x - geometries[1].cellStartX) < 0.0001 })
        XCTAssertTrue(barlines.contains { abs($0.x - geometries[2].cellStartX) < 0.0001 })
        XCTAssertTrue(barlines.contains { abs($0.x - geometries[3].cellStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometries[0].contentStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometries[2].contentStartX) < 0.0001 })
    }

}
