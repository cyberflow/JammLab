import XCTest
@testable import JammLab

final class NotationAttributeGeometryTests: XCTestCase {
    func testNotationMeasureLayoutOffsetsAttributedMeasurePlayheadAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4),
            clef: .treble
        )
        let cellWidth: CGFloat = 148
        let display = NotationAttributeDisplay.full
        let attributeReserveWidth = NotationMeasureLayout.attributeReserveWidth(
            for: attributes,
            display: display
        )

        let attributedStart = NotationMeasureLayout.playheadX(
            measureIndex: 0,
            cellWidth: cellWidth,
            progress: 0,
            attributes: attributes,
            display: display
        )
        let attributedEnd = NotationMeasureLayout.playheadX(
            measureIndex: 0,
            cellWidth: cellWidth,
            progress: 1,
            attributes: attributes,
            display: display
        )
        let ordinaryStart = NotationMeasureLayout.playheadX(
            measureIndex: 1,
            cellWidth: cellWidth,
            progress: 0,
            attributes: attributes,
            display: .none
        )
        let contentStart = NotationMeasureLayout.contentStartX(
            measureIndex: 0,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display
        )
        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display,
            totalWidth: cellWidth * 4
        )
        let barlines = NotationMeasureLayout.barlineGeometries(for: [geometry])

        XCTAssertGreaterThan(attributedStart, AppTheme.Spacing.md)
        XCTAssertEqual(attributedStart, contentStart, accuracy: 0.0001)
        XCTAssertEqual(attributedStart, attributeReserveWidth, accuracy: 0.0001)
        XCTAssertEqual(attributedEnd, contentStart + cellWidth, accuracy: 0.0001)
        XCTAssertEqual(ordinaryStart, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentStartX, attributedStart, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentEndX, contentStart + cellWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentEndX - geometry.contentStartX, cellWidth, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadX(geometry: geometry, progress: 1),
            geometry.rhythmicEndX,
            accuracy: 0.0001
        )
        XCTAssertEqual(geometry.staffStartX, AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertFalse(geometry.includesRawStartBarline)
        XCTAssertTrue(geometry.contentStartsAfterCellBoundary)
        XCTAssertEqual(geometry.leadingBarlineX ?? -1, geometry.staffStartX, accuracy: 0.0001)
        XCTAssertTrue(barlines.contains { abs($0.x - geometry.staffStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometry.contentStartX) < 0.0001 })
        XCTAssertEqual(barlines.count, 2)
        XCTAssertEqual(barlines[1].x, geometry.cellEndX, accuracy: 0.0001)
        XCTAssertTrue(barlines[0].isOuterBoundary)
        XCTAssertTrue(barlines[1].isOuterBoundary)
    }

    func testNotationMeasureLayoutUsesTimeOnlyWidthAtTimeSignatureChange() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let display = NotationAttributeDisplay(
            showsClef: false,
            showsKeySignature: false,
            showsTimeSignature: true
        )
        let cellWidth: CGFloat = 148

        let blockWidth = NotationMeasureLayout.attributeBlockWidth(
            for: attributes,
            display: display,
            cellWidth: cellWidth
        )
        let contentStart = NotationMeasureLayout.contentStartX(
            measureIndex: 2,
            cellWidth: cellWidth,
            attributes: attributes,
            display: display
        )
        let playheadStart = NotationMeasureLayout.playheadX(
            measureIndex: 2,
            cellWidth: cellWidth,
            progress: 0,
            attributes: attributes,
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
        let barlines = NotationMeasureLayout.barlineGeometries(for: [geometry])

        XCTAssertEqual(blockWidth, AppTheme.Timeline.notationTimeSignatureWidth, accuracy: 0.0001)
        XCTAssertEqual(contentStart, playheadStart, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffStartX, geometry.cellStartX, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentStartX, contentStart, accuracy: 0.0001)
        XCTAssertTrue(geometry.includesRawStartBarline)
        XCTAssertTrue(geometry.contentStartsAfterCellBoundary)
        XCTAssertTrue(barlines.contains { abs($0.x - geometry.cellStartX) < 0.0001 })
        XCTAssertFalse(barlines.contains { abs($0.x - geometry.contentStartX) < 0.0001 })
    }

    func testNotationMeasureLayoutUsesThemeClefWidthInFullAttributeReserve() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let blockWidth = NotationMeasureLayout.attributeBlockWidth(
            for: attributes,
            display: .full,
            cellWidth: AppTheme.Timeline.notationMeasureMinWidth
        )
        let reserveWidth = NotationMeasureLayout.attributeReserveWidth(
            for: attributes,
            display: .full
        )
        let expectedBlockWidth = AppTheme.Timeline.notationClefWidth
            + NotationMeasureLayout.keySignatureWidth(for: attributes)
            + AppTheme.Timeline.notationTimeSignatureWidth
            + NotationMeasureLayout.spacingWidth(forVisibleComponentCount: 3)

        XCTAssertEqual(blockWidth, expectedBlockWidth, accuracy: 0.0001)
        XCTAssertEqual(
            reserveWidth,
            AppTheme.Spacing.md + expectedBlockWidth + AppTheme.Spacing.xs,
            accuracy: 0.0001
        )
    }
}
