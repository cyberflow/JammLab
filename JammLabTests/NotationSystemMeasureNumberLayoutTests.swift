import XCTest
@testable import JammLab

final class NotationSystemMeasureNumberLayoutTests: XCTestCase {
    func testNotationMeasureLayoutPositionsSystemMeasureNumberAtStaffStart() {
        let cellWidth: CGFloat = 148
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "C major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let firstGeometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: .full,
            totalWidth: cellWidth * 4
        )

        let labelX = NotationMeasureLayout.systemMeasureNumberLabelX(
            geometry: firstGeometry
        )
        let labelTrailingX = NotationMeasureLayout.systemMeasureNumberLabelTrailingX(
            geometry: firstGeometry
        )
        let expectedTrailingX = firstGeometry.staffStartX + AppTheme.Spacing.sm
        let expectedX = expectedTrailingX - NotationMeasureLayout.measureNumberLabelWidth

        let staffTop: CGFloat = 32
        let labelY = NotationMeasureLayout.systemMeasureNumberLabelY(staffTop: staffTop)
        let shallowLabelY = NotationMeasureLayout.systemMeasureNumberLabelY(
            staffTop: AppTheme.Spacing.xs
        )

        XCTAssertEqual(labelTrailingX, expectedTrailingX, accuracy: 0.0001)
        XCTAssertEqual(
            labelX + NotationMeasureLayout.measureNumberLabelWidth,
            expectedTrailingX,
            accuracy: 0.0001
        )
        XCTAssertEqual(labelX, expectedX, accuracy: 0.0001)
        XCTAssertLessThan(labelX, firstGeometry.staffStartX)
        XCTAssertEqual(
            labelY,
            staffTop - NotationMeasureLayout.systemMeasureNumberStaffGap,
            accuracy: 0.0001
        )
        XCTAssertEqual(shallowLabelY, AppTheme.Spacing.xs, accuracy: 0.0001)
    }
}
