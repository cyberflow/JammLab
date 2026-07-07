import AVFoundation
import XCTest
@testable import JammLab

final class AudioTimingLogicTests: XCTestCase {
    func testDecodedAudioDurationUsesPCMFrameLength() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jammlab-duration-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050)!
        buffer.frameLength = 22_050
        try file.write(from: buffer)

        let duration = try AudioFileImporter.decodedDuration(for: url)

        XCTAssertEqual(duration, 0.5, accuracy: 0.0001)
    }

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

    func testNotationMeasureLayoutPositionsSlashBeatCentersForFourFour() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 10,
            staffEndX: 150
        )

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: .fourFour
        )

        XCTAssertEqual(centers.count, 4)
        XCTAssertEqual(centers[0], 10, accuracy: 0.0001)
        XCTAssertEqual(centers[1], 50, accuracy: 0.0001)
        XCTAssertEqual(centers[2], 90, accuracy: 0.0001)
        XCTAssertEqual(centers[3], 130, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutPositionsSlashBeatCentersAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "Bb major"),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
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

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: attributes.timeSignature
        )
        let beatSpacing = (geometry.contentEndX - geometry.contentStartX) / 3

        XCTAssertEqual(centers.count, 3)
        XCTAssertEqual(
            centers[0],
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[1],
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset + beatSpacing,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            centers[2],
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset + beatSpacing * 2,
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutPositionsSlashBeatCentersForSevenFour() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 1,
            cellStartX: 0,
            cellEndX: 210,
            contentStartX: 0,
            contentEndX: 210,
            staffStartX: 0,
            staffEndX: 210
        )

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4)
        )

        XCTAssertEqual(centers.count, 7)
        XCTAssertEqual(centers[0], 10, accuracy: 0.0001)
        XCTAssertEqual(centers[6], 190, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutPositionsSlashBeatCentersForNonQuarterBeatUnit() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 180,
            contentStartX: 0,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 180
        )
        var sixEight = TimeSignature.fourFour
        sixEight.beatsPerBar = 6
        sixEight.beatUnit = 8

        let centers = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: sixEight
        )

        XCTAssertEqual(centers.count, 6)
        XCTAssertEqual(centers[0], 10, accuracy: 0.0001)
        XCTAssertEqual(centers[1], 40, accuracy: 0.0001)
        XCTAssertEqual(centers[5], 160, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutOmitsSlashBeatCentersWhenContentIsInvalidOrTooNarrow() {
        let zeroWidthGeometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 80,
            contentStartX: 40,
            contentEndX: 40,
            staffStartX: 0,
            staffEndX: 80
        )
        let negativeWidthGeometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 80,
            contentStartX: 50,
            contentEndX: 40,
            staffStartX: 0,
            staffEndX: 80
        )
        let narrowGeometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 40,
            contentStartX: 0,
            contentEndX: 40,
            staffStartX: 0,
            staffEndX: 40
        )

        XCTAssertTrue(NotationMeasureLayout.slashBeatCenters(
            geometry: zeroWidthGeometry,
            timeSignature: .fourFour
        ).isEmpty)
        XCTAssertTrue(NotationMeasureLayout.slashBeatCenters(
            geometry: negativeWidthGeometry,
            timeSignature: .fourFour
        ).isEmpty)
        XCTAssertTrue(NotationMeasureLayout.slashBeatCenters(
            geometry: narrowGeometry,
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4)
        ).isEmpty)
    }

    func testNotationMeasureLayoutAlignsHarmonyAndSlashAnchors() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )
        let slashCenters = NotationMeasureLayout.slashBeatCenters(
            geometry: geometry,
            timeSignature: .fourFour
        )

        let firstHarmonyX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )
        let thirdHarmonyX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )

        XCTAssertEqual(firstHarmonyX, slashCenters[0], accuracy: 0.0001)
        XCTAssertEqual(thirdHarmonyX, slashCenters[2], accuracy: 0.0001)
    }

    func testNotationMeasureLayoutClampsHarmonyAnchorsInsideMeasure() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )

        let endX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: NotationMeasureLayout.quarterLength(for: .fourFour),
            timeSignature: .fourFour
        )
        let outOfRangeX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 99,
            timeSignature: .fourFour
        )

        XCTAssertEqual(endX, geometry.contentEndX, accuracy: 0.0001)
        XCTAssertEqual(outOfRangeX, geometry.contentEndX, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutCentersSingleFullMeasureWholeRest() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let item = NotationMeasureItem(
            id: "whole-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 3,
            displayDuration: NotationDuration(denominator: 1)
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 1.5,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
                clef: .treble
            ),
            notationItems: [item]
        )

        let x = NotationMeasureLayout.notationItemX(
            geometry: geometry,
            measure: measure,
            item: item
        )

        XCTAssertEqual(x, 100, accuracy: 0.0001)
    }

    func testNotationMeasureLayoutDoesNotCenterNonFullMeasureWholeRestCases() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let partialItem = NotationMeasureItem(
            id: "partial",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 1)
        )
        let offsetItem = NotationMeasureItem(
            id: "offset",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 4,
            displayDuration: NotationDuration(denominator: 1)
        )
        let quarterItem = NotationMeasureItem(
            id: "quarter",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )

        for item in [partialItem, offsetItem, quarterItem] {
            let measure = ScoreMeasure(
                number: 1,
                startTime: 0,
                endTime: 2,
                attributes: .defaultTreble,
                notationItems: [item]
            )
            let expectedX = NotationMeasureLayout.harmonyX(
                geometry: geometry,
                offsetInQuarterNotes: item.offsetInQuarterNotes,
                timeSignature: measure.attributes.timeSignature
            )

            XCTAssertEqual(
                NotationMeasureLayout.notationItemX(
                    geometry: geometry,
                    measure: measure,
                    item: item
                ),
                expectedX,
                accuracy: 0.0001
            )
        }

        let firstSplitItem = NotationMeasureItem(
            id: "split-a",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 1)
        )
        let secondSplitItem = NotationMeasureItem(
            id: "split-b",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        let splitMeasure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [firstSplitItem, secondSplitItem]
        )

        XCTAssertEqual(
            NotationMeasureLayout.notationItemX(
                geometry: geometry,
                measure: splitMeasure,
                item: firstSplitItem
            ),
            NotationMeasureLayout.harmonyX(
                geometry: geometry,
                offsetInQuarterNotes: firstSplitItem.offsetInQuarterNotes,
                timeSignature: splitMeasure.attributes.timeSignature
            ),
            accuracy: 0.0001
        )
    }

    func testNotationMeasureLayoutMapsAnchorXBackToProgress() {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 160,
            contentStartX: 0,
            contentEndX: 160,
            staffStartX: 0,
            staffEndX: 160
        )
        let firstAnchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: .fourFour
        )
        let thirdAnchorX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 2,
            timeSignature: .fourFour
        )

        XCTAssertEqual(
            NotationMeasureLayout.notationAnchorProgress(atX: firstAnchorX, geometry: geometry),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotationMeasureLayout.notationAnchorProgress(atX: thirdAnchorX, geometry: geometry),
            0.5,
            accuracy: 0.0001
        )
    }

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

    func testNotationMeasureLayoutPositionsHarmonyAfterAttributes() {
        let attributes = MeasureAttributes(
            keySignature: KeySignature.normalized(from: "F major"),
            timeSignature: TimeSignature(beatsPerBar: 7, beatUnit: 4),
            clef: .treble
        )
        let cellWidth: CGFloat = 148
        let geometry = NotationMeasureLayout.canvasGeometry(
            measureIndex: 0,
            measureCount: 4,
            cellWidth: cellWidth,
            attributes: attributes,
            display: .full,
            totalWidth: cellWidth * 4
        )

        let harmonyStartX = NotationMeasureLayout.harmonyX(
            geometry: geometry,
            offsetInQuarterNotes: 0,
            timeSignature: attributes.timeSignature
        )

        XCTAssertEqual(
            harmonyStartX,
            geometry.contentStartX + AppTheme.Timeline.notationItemAnchorInset,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(harmonyStartX, geometry.cellStartX)
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
