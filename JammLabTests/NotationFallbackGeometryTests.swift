import XCTest
@testable import JammLab

final class NotationFallbackGeometryTests: XCTestCase {
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
            geometries[0].rhythmicStartX,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureLayout.playheadIndicatorX(
                geometry: geometries[0],
                progress: 0,
                indicatorWidth: AppTheme.Stroke.thick
            ),
            geometries[0].rhythmicStartX,
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
