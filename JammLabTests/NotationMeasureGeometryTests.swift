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
            geometries[3].rhythmicEndX,
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

    func testBarlineHitTargetsMapVisibleBoundariesToMeasureTimes() {
        let geometries = NotationMeasureLayout.fallbackCanvasGeometries(
            measureCount: 3,
            totalWidth: 300
        )
        let measures = [
            scoreMeasure(number: 1, start: 0, end: 2),
            scoreMeasure(number: 2, start: 2, end: 4),
            scoreMeasure(number: 3, start: 4, end: 6)
        ]

        let targets = NotationMeasureLayout.barlineHitTargets(
            for: geometries,
            measures: measures
        )

        XCTAssertEqual(targets.map(\.measureIndex), [0, 1, 2, 2])
        XCTAssertEqual(targets.map(\.boundary), [.leading, .leading, .leading, .trailing])
        XCTAssertEqual(targets.map(\.id), ["0-leading", "1-leading", "2-leading", "2-trailing"])
        XCTAssertEqual(targets.map(\.targetTime), [0, 2, 4, 6])
        XCTAssertEqual(targets[0].x, geometries[0].staffStartX, accuracy: 0.0001)
        XCTAssertEqual(targets[1].x, geometries[1].cellStartX, accuracy: 0.0001)
        XCTAssertEqual(targets[3].x, geometries[2].staffEndX, accuracy: 0.0001)
    }

    func testBarlineHitTargetsKeepAttributedMeasureBoundaryTimes() {
        let fullAttributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: .fourFour,
            clef: .treble
        )
        let changedAttributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "Bb major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            clef: .treble
        )
        let firstReserve = NotationMeasureLayout.attributeReserveWidth(
            for: fullAttributes,
            display: .full
        )
        let secondReserve = NotationMeasureLayout.attributeReserveWidth(
            for: changedAttributes,
            display: .full
        )
        let geometries = NotationMeasureLayout.canvasGeometries(
            measureCount: 2,
            totalWidth: 300 + firstReserve + secondReserve,
            attributeReserveWidths: [firstReserve, secondReserve]
        )
        let measures = [
            scoreMeasure(number: 1, start: 0, end: 2, attributes: fullAttributes),
            scoreMeasure(number: 2, start: 2, end: 3.5, attributes: changedAttributes)
        ]

        let targets = NotationMeasureLayout.barlineHitTargets(
            for: geometries,
            measures: measures
        )

        XCTAssertEqual(targets.map(\.targetTime), [0, 2, 3.5])
        XCTAssertEqual(targets.map(\.id), ["0-leading", "1-leading", "1-trailing"])
        XCTAssertEqual(targets[1].x, geometries[1].cellStartX, accuracy: 0.0001)
        XCTAssertNotEqual(targets[1].x, geometries[1].contentStartX, accuracy: 0.0001)
    }

    func testBarlineHitTargetIDsStayStableWhenOnlyTimesChange() {
        let geometries = NotationMeasureLayout.fallbackCanvasGeometries(
            measureCount: 2,
            totalWidth: 200
        )
        let originalMeasures = [
            scoreMeasure(number: 1, start: 0, end: 2),
            scoreMeasure(number: 2, start: 2, end: 4)
        ]
        let retimedMeasures = [
            scoreMeasure(number: 1, start: 1, end: 3),
            scoreMeasure(number: 2, start: 3, end: 5)
        ]

        let originalTargets = NotationMeasureLayout.barlineHitTargets(
            for: geometries,
            measures: originalMeasures
        )
        let retimedTargets = NotationMeasureLayout.barlineHitTargets(
            for: geometries,
            measures: retimedMeasures
        )

        XCTAssertEqual(retimedTargets.map(\.id), originalTargets.map(\.id))
        XCTAssertNotEqual(retimedTargets.map(\.targetTime), originalTargets.map(\.targetTime))
    }

    func testNotationRenderSceneCacheReusesPureGeometrySnapshot() {
        let measures = [
            scoreMeasure(number: 1, start: 0, end: 2),
            scoreMeasure(number: 2, start: 2, end: 4)
        ]
        let input = NotationTrackRenderScene.Input(
            visibleMeasures: measures,
            measureLayout: nil,
            renderedMeasureCount: 2,
            width: 600,
            attributeDisplays: [.full, .none],
            attributeReserveWidths: [80, 0]
        )
        let cache = NotationTrackRenderSceneCache()

        let first = cache.scene(input: input)
        let second = cache.scene(input: input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(first.geometries.count, 2)
        XCTAssertEqual(first.barlineHitTargets.map(\.targetTime), [0, 2, 4])
    }

    func testNotationRenderSceneCacheInvalidatesForWidthOrScoreChanges() {
        let measure = scoreMeasure(number: 1, start: 0, end: 2)
        let input = NotationTrackRenderScene.Input(
            visibleMeasures: [measure],
            measureLayout: nil,
            renderedMeasureCount: 1,
            width: 300,
            attributeDisplays: [.full],
            attributeReserveWidths: [80]
        )
        let cache = NotationTrackRenderSceneCache()
        _ = cache.scene(input: input)
        var resizedInput = input
        resizedInput.width = 500
        _ = cache.scene(input: resizedInput)
        var changedScoreInput = resizedInput
        changedScoreInput.visibleMeasures = [
            scoreMeasure(number: 1, start: 0, end: 3)
        ]
        _ = cache.scene(input: changedScoreInput)

        XCTAssertEqual(cache.buildCount, 3)
    }

    func testNotationPartPlannerAlwaysKeepsAnAvailablePartVisible() {
        let available: [NotationPartDescriptor] = [.main, .stem(.vocals)]

        XCTAssertEqual(
            NotationPartStatePlanner.normalizedVisiblePartIDs([], availableParts: available),
            [.main]
        )
        XCTAssertEqual(
            NotationPartStatePlanner.normalizedVisiblePartIDs(
                [.stem(.vocals), .stem(.drums)],
                availableParts: available
            ),
            [.stem(.vocals)]
        )
    }

    private func scoreMeasure(
        number: Int,
        start: TimeInterval,
        end: TimeInterval,
        attributes: MeasureAttributes = MeasureAttributes(
            keySignature: .cMajor,
            timeSignature: .fourFour,
            clef: .treble
        )
    ) -> ScoreMeasure {
        ScoreMeasure(
            number: number,
            startTime: start,
            endTime: end,
            attributes: attributes
        )
    }

}
