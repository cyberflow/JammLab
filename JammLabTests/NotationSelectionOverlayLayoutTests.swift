import XCTest
@testable import JammLab

final class NotationSelectionOverlayLayoutTests: XCTestCase {
    func testNotationMeasureLayoutGroupsContiguousSelectionOverlayRuns() {
        let geometries = selectionOverlayTestGeometries(count: 4, width: 100)

        let runs = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [1, 2],
            geometries: geometries
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].startMeasureIndex, 1)
        XCTAssertEqual(runs[0].endMeasureIndex, 2)
        XCTAssertEqual(runs[0].x, geometries[1].cellStartX, accuracy: 0.0001)
        XCTAssertEqual(runs[0].width, geometries[2].cellEndX - geometries[1].cellStartX, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutKeepsSingleAndNonContiguousSelectionOverlayRunsSeparate() {
        let geometries = selectionOverlayTestGeometries(count: 4, width: 100)

        let singleRun = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [1],
            geometries: geometries
        )
        let separatedRuns = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [0, 2],
            geometries: geometries
        )

        XCTAssertEqual(singleRun.map(\.startMeasureIndex), [1])
        XCTAssertEqual(singleRun.map(\.endMeasureIndex), [1])
        XCTAssertEqual(separatedRuns.map(\.startMeasureIndex), [0, 2])
        XCTAssertEqual(separatedRuns.map(\.endMeasureIndex), [0, 2])
    }

    func testNotationMeasureLayoutNormalizesSelectionOverlayRunIndices() {
        let geometries = selectionOverlayTestGeometries(count: 4, width: 100)

        let runs = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [2, 1, 1, -1, 9],
            geometries: geometries
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].startMeasureIndex, 1)
        XCTAssertEqual(runs[0].endMeasureIndex, 2)
    }

    func testNotationMeasureLayoutSelectionOverlayRunsStayWithinProvidedRowGeometry() {
        let rowGeometries = selectionOverlayTestGeometries(count: 2, width: 100)

        let runs = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [0, 1, 2],
            geometries: rowGeometries
        )
        let emptyRuns = NotationMeasureLayout.selectionOverlayRuns(
            selectedMeasureIndices: [],
            geometries: rowGeometries
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].startMeasureIndex, 0)
        XCTAssertEqual(runs[0].endMeasureIndex, 1)
        XCTAssertEqual(emptyRuns, [])
    }

    private func selectionOverlayTestGeometries(
        count: Int,
        width: CGFloat
    ) -> [NotationMeasureCanvasGeometry] {
        (0..<count).map { index in
            let startX = CGFloat(index) * width
            return NotationMeasureCanvasGeometry(
                measureIndex: index,
                cellStartX: startX,
                cellEndX: startX + width,
                contentStartX: startX,
                contentEndX: startX + width,
                staffStartX: startX,
                staffEndX: startX + width
            )
        }
    }
}
