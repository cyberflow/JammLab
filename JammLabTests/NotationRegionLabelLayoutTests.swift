import XCTest
@testable import JammLab

final class NotationRegionLabelLayoutTests: XCTestCase {
    func testNotationMeasureLayoutKeepsRegionLabelAboveHarmonyLabel() {
        let staffTop: CGFloat = 50

        let regionY = NotationMeasureLayout.regionLabelY(staffTop: staffTop)
        let harmonyY = NotationMeasureLayout.harmonyLabelY(staffTop: staffTop)

        XCTAssertLessThan(regionY, harmonyY)
        XCTAssertLessThanOrEqual(
            regionY
                + AppTheme.Timeline.notationRegionLabelHeight
                + AppTheme.Timeline.notationRegionLabelGap,
            harmonyY + 0.0001
        )
    }

    func testNotationMeasureLayoutKeepsFirstRegionLabelAfterMeasureNumber() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 180,
            contentStartX: 0,
            contentEndX: 180,
            staffStartX: 10,
            staffEndX: 180
        )

        let x = NotationMeasureLayout.regionLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour,
            avoidsSystemMeasureNumber: true
        )
        let minimumX = NotationMeasureLayout.systemMeasureNumberLabelTrailingX(
            geometry: geometry
        ) + AppTheme.Spacing.sm

        XCTAssertGreaterThanOrEqual(x, minimumX)
    }

    func testNotationMeasureLayoutClampsRegionLabelInsideVisibleBounds() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 180,
            cellEndX: 360,
            contentStartX: 180,
            contentEndX: 360,
            staffStartX: 180,
            staffEndX: 350
        )
        let labelWidth: CGFloat = 64

        let x = NotationMeasureLayout.regionLabelX(
            geometry: geometry,
            offsetInQuarterNotes: 99,
            timeSignature: .fourFour,
            labelWidth: labelWidth
        )

        XCTAssertGreaterThanOrEqual(x, geometry.staffStartX)
        XCTAssertLessThanOrEqual(x + labelWidth, geometry.staffEndX + 0.0001)
    }
}
