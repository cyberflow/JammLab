import XCTest
@testable import JammLab

final class NotationHarmonyLabelLayoutTests: XCTestCase {
    func testNotationMeasureLayoutPositionsHarmonyLabelBeforeInnerBeatAnchor() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )

        let anchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )
        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )

        XCTAssertEqual(
            labelX,
            anchorX - AppTheme.Timeline.notationHarmonyAnchorLeadingOffset,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutClampsFirstHarmonyLabelToVisibleStaffStart() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: AppTheme.Timeline.notationStaffHorizontalInset,
            staffEndX: 150
        )

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )

        XCTAssertEqual(labelX, geometry.staffStartX, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutKeepsAttributedFirstHarmonyLabelAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
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

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: attributes.timeSignature
        )
        let anchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: attributes.timeSignature
        )

        XCTAssertGreaterThanOrEqual(labelX, geometry.contentStartX)
        XCTAssertEqual(
            labelX,
            anchorX - AppTheme.Timeline.notationHarmonyAnchorLeadingOffset,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutPositionsNonFirstMeasureHarmonyLabelNearContentStart() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 160,
            cellEndX: 320,
            contentStartX: 160,
            contentEndX: 320,
            staffStartX: 160,
            staffEndX: 320
        )

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )
        let anchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )

        XCTAssertGreaterThanOrEqual(labelX, geometry.contentStartX)
        XCTAssertEqual(
            labelX,
            anchorX - AppTheme.Timeline.notationHarmonyAnchorLeadingOffset,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutKeepsHarmonyLabelXBoundedForInvalidGeometry() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 40,
            contentStartX: 40,
            contentEndX: 40,
            staffStartX: 20,
            staffEndX: 40
        )

        let labelX = NotationMeasureLayout.harmonyLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 99,
            timeSignature: .fourFour
        )

        XCTAssertFalse(labelX.isNaN)
        XCTAssertEqual(labelX, geometry.contentStartX, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutKeepsHarmonyLabelAboveStaff() {
        let defaultStaffTop: CGFloat = 32
        let lowerStaffTop: CGFloat = 60

        let defaultY = NotationMeasureLayout.harmonyLabelY(staffTop: defaultStaffTop)
        let lowerY = NotationMeasureLayout.harmonyLabelY(staffTop: lowerStaffTop)

        XCTAssertEqual(defaultY, AppTheme.Spacing.xs, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(
            defaultY + AppTheme.ControlSize.abletonNumberFieldHeight + AppTheme.Spacing.xs,
            defaultStaffTop
        )
        XCTAssertEqual(
            lowerY + AppTheme.ControlSize.abletonNumberFieldHeight + AppTheme.Spacing.xs,
            lowerStaffTop,
            accuracy: 0.0001
        )
    }
}
