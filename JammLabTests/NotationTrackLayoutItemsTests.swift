import XCTest
@testable import JammLab

final class NotationTrackLayoutItemsTests: XCTestCase {
    func testNotationTrackLayoutItemsBuildsMeasureItemsFromPureInputs() throws {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 520,
            contentStartX: 0,
            contentEndX: 520,
            staffStartX: 20,
            staffEndX: 520
        )
        let firstRegionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondRegionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let harmonyID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let notationItem = NotationMeasureItem(
            id: "quarter-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let harmony = HarmonySymbol(
            id: harmonyID,
            time: 1,
            measureNumber: 1,
            offsetInQuarterNotes: 2,
            rawText: "G7"
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [notationItem],
            harmonies: [harmony],
            regionLabels: [
                NotationRegionLabel(
                    id: firstRegionID,
                    time: 0,
                    measureNumber: 1,
                    offsetInQuarterNotes: 0,
                    title: "Intro"
                ),
                NotationRegionLabel(
                    id: secondRegionID,
                    time: 0.25,
                    measureNumber: 1,
                    offsetInQuarterNotes: 0,
                    title: "Verse"
                )
            ]
        )

        let regionItems = NotationTrackLayoutItems.regionLabels(
            visibleMeasures: [measure],
            geometries: [geometry]
        )
        let harmonyItems = NotationTrackLayoutItems.harmonies(
            visibleMeasures: [measure],
            geometries: [geometry]
        )
        let notationItems = NotationTrackLayoutItems.notationItems(
            visibleMeasures: [measure],
            geometries: [geometry]
        )

        XCTAssertEqual(regionItems.map(\.label.id), [firstRegionID, secondRegionID])
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(regionItems.first).x,
            NotationMeasureLayout.systemMeasureNumberLabelTrailingX(geometry: geometry)
                + AppTheme.Spacing.sm
        )
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(regionItems.last).x,
            try XCTUnwrap(regionItems.first).x
                + AppTheme.Timeline.notationRegionLabelMaxWidth
                + AppTheme.Timeline.notationRegionLabelGap
                - 0.0001
        )

        let harmonyItem = try XCTUnwrap(harmonyItems.first)
        XCTAssertEqual(harmonyItem.symbol, harmony)
        XCTAssertEqual(
            harmonyItem.x,
            NotationMeasureLayout.harmonyLabelX(
                geometry: geometry,
                offsetInQuarterNotes: harmony.offsetInQuarterNotes,
                timeSignature: measure.attributes.timeSignature
            ),
            accuracy: 0.0001
        )

        let layoutNotationItem = try XCTUnwrap(notationItems.first)
        XCTAssertEqual(layoutNotationItem.notationItem, notationItem)
        XCTAssertTrue(layoutNotationItem.selection.matches(measure, item: notationItem))
        XCTAssertEqual(
            layoutNotationItem.x,
            NotationMeasureLayout.notationItemX(
                geometry: geometry,
                measure: measure,
                item: notationItem
            ),
            accuracy: 0.0001
        )
    }
}
