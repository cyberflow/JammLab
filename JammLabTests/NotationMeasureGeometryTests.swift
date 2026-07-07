import XCTest
@testable import JammLab

final class NotationMeasureGeometryTests: XCTestCase {
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
            geometry.contentEndX,
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

    func testNotationMeasureLayoutFallbackGeometryPreservesSymmetricOuterInsets() {
        let totalWidth: CGFloat = 296

        let geometries = NotationMeasureLayout.fallbackCanvasGeometries(
            measureCount: 0,
            totalWidth: totalWidth
        )
        let barlines = NotationMeasureLayout.barlineGeometries(for: geometries)

        XCTAssertEqual(geometries.count, 1)
        XCTAssertEqual(geometries[0].contentStartX, 0, accuracy: 0.0001)
        XCTAssertEqual(geometries[0].staffStartX, AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertEqual(geometries[0].staffEndX, totalWidth - AppTheme.Timeline.notationStaffHorizontalInset, accuracy: 0.0001)
        XCTAssertTrue(geometries[0].includesRawStartBarline)
        XCTAssertFalse(geometries[0].contentStartsAfterCellBoundary)
        XCTAssertEqual(geometries[0].leadingBarlineX ?? -1, geometries[0].staffStartX, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, geometries[0].staffEndX, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadX(geometry: geometries[0], progress: 0),
            geometries[0].contentStartX,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureLayout.playheadIndicatorX(
                geometry: geometries[0],
                progress: 0,
                indicatorWidth: AppTheme.Stroke.thick
            ),
            geometries[0].staffStartX,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutClampsSymmetricOuterInsetsForNarrowWidth() {
        let inset = AppTheme.Timeline.notationStaffHorizontalInset
        let totalWidth = inset * 1.5

        let geometries = NotationMeasureLayout.fallbackCanvasGeometries(
            measureCount: 1,
            totalWidth: totalWidth
        )
        let geometry = geometries[0]
        let barlines = NotationMeasureLayout.barlineGeometries(for: geometries)

        XCTAssertEqual(geometry.staffStartX, inset, accuracy: 0.0001)
        XCTAssertEqual(geometry.staffEndX, geometry.staffStartX, accuracy: 0.0001)
        XCTAssertEqual(barlines.first?.x ?? -1, geometry.staffStartX, accuracy: 0.0001)
        XCTAssertEqual(barlines.last?.x ?? -1, geometry.staffEndX, accuracy: 0.0001)
        XCTAssertEqual(
            NotationMeasureLayout.playheadIndicatorX(
                geometry: geometry,
                progress: 1,
                indicatorWidth: AppTheme.Stroke.thick
            ),
            geometry.staffStartX,
            accuracy: 0.0001
        )
    }
}
