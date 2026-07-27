import CoreGraphics
import XCTest
@testable import JammLab

final class NotationVisibleMeasureFitterTests: XCTestCase {
    func testNotationVisibleMeasureFitterChoosesCountForAvailableWidth() {
        let minimumWidth = AppTheme.Timeline.notationMeasureMinWidth
        let stateForMeasureCount: (Int) -> NotationViewportState = {
            NotationViewportState.pending(visibleMeasureCount: $0)
        }

        XCTAssertEqual(
            NotationVisibleMeasureFitter.fittedMeasureCount(
                availableWidth: minimumWidth * 8,
                maximumMeasureCount: 8,
                stateForMeasureCount: stateForMeasureCount
            ),
            8
        )
        XCTAssertEqual(
            NotationVisibleMeasureFitter.fittedMeasureCount(
                availableWidth: minimumWidth * 4 + 10,
                maximumMeasureCount: 8,
                stateForMeasureCount: stateForMeasureCount
            ),
            4
        )
        XCTAssertEqual(
            NotationVisibleMeasureFitter.fittedMeasureCount(
                availableWidth: minimumWidth * 0.5,
                maximumMeasureCount: 8,
                stateForMeasureCount: stateForMeasureCount
            ),
            1
        )
    }

    func testNotationVisibleMeasureFitterAccountsForAttributeReserveWidth() {
        let tempoMap = fourFourTempoMap(duration: 120)
        let availableWidth = AppTheme.Timeline.notationMeasureMinWidth * 4
        let stateForMeasureCount: (Int) -> NotationViewportState = { count in
            self.notationViewportState(
                tempoMap: tempoMap,
                currentTime: 0,
                keyName: "D major",
                visibleMeasureCount: count
            )
        }

        let fittedCount = NotationVisibleMeasureFitter.fittedMeasureCount(
            availableWidth: availableWidth,
            maximumMeasureCount: 4,
            stateForMeasureCount: stateForMeasureCount
        )
        let fittedState = stateForMeasureCount(fittedCount)
        let fourMeasureState = stateForMeasureCount(4)

        XCTAssertLessThan(fittedCount, 4)
        XCTAssertLessThanOrEqual(
            NotationVisibleMeasureFitter.minimumRequiredWidth(for: fittedState),
            availableWidth + NotationVisibleMeasureFitter.widthTolerance
        )
        XCTAssertGreaterThan(
            NotationVisibleMeasureFitter.minimumRequiredWidth(for: fourMeasureState),
            availableWidth + NotationVisibleMeasureFitter.widthTolerance
        )
    }

    func testNotationVisibleMeasureFitterFallsBackToOneWhenPreferredSingleMeasureIsTooWide() {
        let tempoMap = fourFourTempoMap(duration: 120)
        let availableWidth: CGFloat = 10
        let stateForMeasureCount: (Int) -> NotationViewportState = { count in
            self.notationViewportState(
                tempoMap: tempoMap,
                currentTime: 0,
                keyName: "D major",
                visibleMeasureCount: count
            )
        }

        let fittedCount = NotationVisibleMeasureFitter.fittedMeasureCount(
            availableWidth: availableWidth,
            maximumMeasureCount: 8,
            stateForMeasureCount: stateForMeasureCount
        )

        XCTAssertEqual(fittedCount, 1)
        XCTAssertGreaterThan(
            NotationVisibleMeasureFitter.minimumRequiredWidth(for: stateForMeasureCount(1)),
            availableWidth
        )
    }

    private func fourFourTempoMap(duration: TimeInterval) -> TempoMap {
        TempoMap(
            baseSettings: BeatGridSettings(
                bpm: 120,
                firstBeatTime: 0,
                timeSignature: .fourFour
            ),
            markers: [],
            duration: duration
        )
    }

    private func notationViewportState(
        tempoMap: TempoMap,
        currentTime: TimeInterval,
        keyName: String? = "C major",
        visibleMeasureCount: Int = 8
    ) -> NotationViewportState {
        NotationViewportFactory().viewportState(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            currentTime: currentTime,
            playbackMarkerTime: 0,
            isPlaying: true,
            keyName: keyName,
            visibleMeasureCount: visibleMeasureCount,
            harmonySymbols: [],
            notes: []
        )
    }
}

final class NotationSystemMeasureLayoutTests: XCTestCase {
    func testDenseMeasureReceivesMoreWidthThanSparseNeighbor() throws {
        let dense = scoreMeasure(
            number: 1,
            startTime: 0,
            items: stride(from: 0.0, through: 3.75, by: 0.25).enumerated().map {
                index,
                offset in
                notationItem(id: "dense-\(index)", measureNumber: 1, offset: offset)
            }
        )
        let sparse = scoreMeasure(
            number: 2,
            startTime: 2,
            items: [notationItem(id: "sparse", measureNumber: 2, offset: 0)]
        )
        let layout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[dense, sparse]])
        )
        let geometries = layout.geometries(totalWidth: layout.minimumRequiredWidth)

        XCTAssertGreaterThan(layout.slots[0].minimumBodyWidth, layout.slots[1].minimumBodyWidth)
        XCTAssertGreaterThan(
            geometries[0].contentEndX - geometries[0].contentStartX,
            geometries[1].contentEndX - geometries[1].contentStartX
        )
    }

    func testSharedLayoutUsesDensestPartAndKeepsAlignedMeasureBoundaries() throws {
        let denseMain = scoreMeasure(
            number: 1,
            startTime: 0,
            items: [
                notationItem(id: "main-a", measureNumber: 1, offset: 3.5),
                notationItem(id: "main-b", measureNumber: 1, offset: 3.75)
            ]
        )
        let sparseBass = scoreMeasure(
            number: 1,
            startTime: 0,
            items: [notationItem(id: "bass", measureNumber: 1, offset: 0)]
        )
        let layout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[denseMain], [sparseBass]])
        )
        let geometry = try XCTUnwrap(
            layout.geometries(totalWidth: layout.minimumRequiredWidth).first
        )
        let lateX = NotationMeasureLayout.notationItemX(
            geometry: geometry,
            measure: denseMain,
            item: try XCTUnwrap(denseMain.notationItems.last)
        )

        XCTAssertGreaterThan(
            layout.slots[0].trailingAnchorInset,
            AppTheme.Timeline.notationItemAnchorInset
        )
        XCTAssertLessThanOrEqual(
            lateX
                + AppTheme.Timeline.notationRhythmicGlyphRadius
                + AppTheme.Timeline.notationRhythmicColumnGap,
            geometry.staffEndX + 0.0001
        )
        XCTAssertTrue(layout.matches([sparseBass]))
    }

    func testLateSixteenthPairUsesCompactSpacingWithoutStretchingWholeMeasure() throws {
        let measure = scoreMeasure(
            number: 1,
            startTime: 0,
            items: [
                notationItem(id: "late-a", measureNumber: 1, offset: 3.5),
                notationItem(id: "late-b", measureNumber: 1, offset: 3.75)
            ]
        )
        let layout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[measure]])
        )
        let geometry = try XCTUnwrap(
            layout.geometries(totalWidth: layout.minimumRequiredWidth).first
        )
        let itemXs = measure.notationItems.map {
            NotationMeasureLayout.notationItemX(
                geometry: geometry,
                measure: measure,
                item: $0
            )
        }
        let minimumColumnDistance =
            AppTheme.Timeline.notationRhythmicGlyphRadius * 2
            + AppTheme.Timeline.notationRhythmicColumnGap
        let firstItemX = try XCTUnwrap(itemXs.first)
        let lastItemX = try XCTUnwrap(itemXs.last)

        XCTAssertLessThan(
            layout.slots[0].minimumBodyWidth,
            AppTheme.Timeline.notationMeasureMinWidth * 1.5
        )
        XCTAssertGreaterThanOrEqual(
            lastItemX - firstItemX,
            minimumColumnDistance - 0.0001
        )
    }

    func testRhythmicMapRoundTripsAnchorsAndKeepsPlayheadAligned() throws {
        let measure = scoreMeasure(
            number: 1,
            startTime: 0,
            items: [
                notationItem(id: "early", measureNumber: 1, offset: 0.25),
                notationItem(id: "late-a", measureNumber: 1, offset: 3.5),
                notationItem(id: "late-b", measureNumber: 1, offset: 3.75)
            ]
        )
        let layout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[measure]])
        )
        let geometry = try XCTUnwrap(
            layout.geometries(totalWidth: layout.minimumRequiredWidth + 240).first
        )

        for progress in [0.0, 0.0625, 0.5, 0.875, 0.9375, 1.0] {
            let x = NotationMeasureLayout.notationAnchorX(
                geometry: geometry,
                offsetInQuarterNotes: progress * 4,
                timeSignature: .fourFour
            )

            XCTAssertEqual(
                NotationMeasureLayout.notationAnchorProgress(
                    atX: x,
                    geometry: geometry
                ),
                progress,
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                NotationMeasureLayout.playheadX(
                    geometry: geometry,
                    progress: CGFloat(progress)
                ),
                x,
                accuracy: 0.0001
            )
        }
    }

    func testCompressedRhythmicMapStillRoundTripsHitTesting() throws {
        let measure = scoreMeasure(
            number: 1,
            startTime: 0,
            items: stride(from: 0.0, through: 3.75, by: 0.25).enumerated().map {
                notationItem(
                    id: "compressed-\($0.offset)",
                    measureNumber: 1,
                    offset: $0.element
                )
            }
        )
        let layout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[measure]])
        )
        let geometry = try XCTUnwrap(
            layout.geometries(totalWidth: layout.minimumRequiredWidth * 0.75).first
        )
        let rhythmicWidth = geometry.rhythmicEndX - geometry.rhythmicStartX

        XCTAssertLessThan(
            rhythmicWidth,
            layout.slots[0].rhythmicSpacingMap.compactSpan
        )
        for progress in [0.0, 0.125, 0.5, 0.875, 1.0] {
            let x = NotationMeasureLayout.playheadX(
                geometry: geometry,
                progress: CGFloat(progress)
            )
            XCTAssertEqual(
                NotationMeasureLayout.notationAnchorProgress(
                    atX: x,
                    geometry: geometry
                ),
                progress,
                accuracy: 0.000_001
            )
        }
    }

    func testComplexChordFootprintsStayInsideStaffAtMeasureEdges() throws {
        let earlyItems = complexChordItems(offset: 0, idPrefix: "early")
        let lateItems = complexChordItems(offset: 3.75, idPrefix: "late")
        let measure = scoreMeasure(
            number: 1,
            startTime: 0,
            items: earlyItems + lateItems
        )
        let layout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[measure]])
        )
        let geometry = try XCTUnwrap(
            layout.geometries(totalWidth: layout.minimumRequiredWidth).first
        )
        let chordLayout = NotationHorizontalLayoutResolver.chordLayout(in: measure)
        let accidentalColumns =
            NotationHorizontalLayoutResolver.accidentalColumnByItemID(in: measure)
        let gap = AppTheme.Timeline.notationRhythmicColumnGap

        for item in measure.notationItems {
            let anchorX = NotationMeasureLayout.notationItemX(
                geometry: geometry,
                measure: measure,
                item: item
            )
            let xOffset = chordLayout.xOffsetByItemID[item.id] ?? 0
            var leftEdge = anchorX + xOffset
                - AppTheme.Timeline.notationRhythmicGlyphRadius
            var rightEdge = anchorX + xOffset
                + AppTheme.Timeline.notationRhythmicGlyphRadius

            if let accidentalColumn = accidentalColumns[item.id] {
                let accidentalCenter = anchorX + xOffset
                    - AppTheme.Timeline.notationInlineAccidentalNoteOffset
                    - CGFloat(accidentalColumn)
                        * AppTheme.Timeline.notationInlineAccidentalColumnSpacing
                leftEdge = min(
                    leftEdge,
                    accidentalCenter - AppTheme.Timeline.notationAccidentalWidth / 2
                )
            }
            if item.displayDuration.isDotted {
                rightEdge = max(
                    rightEdge,
                    anchorX
                        + xOffset
                        + AppTheme.Timeline.notationStaffLineSpacing
                        + AppTheme.Timeline.notationRhythmicDotRadius
                )
            }

            XCTAssertGreaterThanOrEqual(
                leftEdge,
                geometry.staffStartX + gap - 0.0001
            )
            XCTAssertLessThanOrEqual(
                rightEdge,
                geometry.staffEndX - gap + 0.0001
            )
        }
    }

    func testIntermediateAnchorInAnotherPartDoesNotCreateCrossStaffCollisionConstraint() throws {
        let main = scoreMeasure(
            number: 1,
            startTime: 0,
            items: [
                notationItem(id: "main-a", measureNumber: 1, offset: 0),
                notationItem(id: "main-b", measureNumber: 1, offset: 0.25)
            ]
        )
        let bass = scoreMeasure(
            number: 1,
            startTime: 0,
            items: [
                notationItem(id: "bass-middle", measureNumber: 1, offset: 0.125)
            ]
        )
        let mainOnlyLayout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[main]])
        )
        let sharedLayout = try XCTUnwrap(
            NotationSystemMeasureLayout.make(measureRows: [[main], [bass]])
        )

        XCTAssertEqual(
            sharedLayout.slots[0].rhythmicSpacingMap.compactSpan,
            mainOnlyLayout.slots[0].rhythmicSpacingMap.compactSpan,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            sharedLayout.slots[0].minimumBodyWidth,
            mainOnlyLayout.slots[0].minimumBodyWidth,
            accuracy: 0.0001
        )
    }

    private func scoreMeasure(
        number: Int,
        startTime: TimeInterval,
        items: [NotationMeasureItem]
    ) -> ScoreMeasure {
        ScoreMeasure(
            number: number,
            startTime: startTime,
            endTime: startTime + 2,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: .fourFour,
                clef: .treble
            ),
            notationItems: items
        )
    }

    private func notationItem(
        id: String,
        measureNumber: Int,
        offset: Double
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: measureNumber,
            measureStartTime: TimeInterval(measureNumber - 1) * 2,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: 0.25,
            displayDuration: NotationDuration(denominator: 16)
        )
    }

    private func complexChordItems(
        offset: Double,
        idPrefix: String
    ) -> [NotationMeasureItem] {
        [
            NotationMeasureItem(
                id: "\(idPrefix)-short",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                explicitAccidental: .sharp,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: offset,
                durationInQuarterNotes: 0.375,
                displayDuration: NotationDuration(denominator: 16, isDotted: true)
            ),
            NotationMeasureItem(
                id: "\(idPrefix)-second",
                kind: .note,
                pitch: NotationPitch(step: .d, octave: 4),
                explicitAccidental: .flat,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: offset,
                durationInQuarterNotes: 0.25,
                displayDuration: NotationDuration(denominator: 16)
            ),
            NotationMeasureItem(
                id: "\(idPrefix)-duplicate",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                explicitAccidental: .natural,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: offset,
                durationInQuarterNotes: 0.5,
                displayDuration: NotationDuration(denominator: 8)
            )
        ]
    }
}

final class NotationWindowScoreLayoutTests: XCTestCase {
    func testMultiPartLayoutAlignsMeasureRangesAndHostsRegionsOnTopStaffOnly() {
        let partStates = [
            partState(part: .main, currentTime: 5.1),
            partState(part: .stem(.bass), currentTime: 5.1),
            partState(part: .stem(.drums), currentTime: 5.1)
        ]

        let layout = NotationWindowScoreLayout.make(
            partStates: partStates,
            contentWidth: 1_400
        )

        XCTAssertTrue(layout.usesPartGutter)
        XCTAssertEqual(layout.measuresPerSystem, AppTheme.NotationWindow.maximumMeasuresPerSystem)
        XCTAssertFalse(layout.systems.isEmpty)
        XCTAssertNotNil(layout.activeSystemID)
        for system in layout.systems {
            XCTAssertEqual(system.staves.map(\.part.id), [.main, .stem(.bass), .stem(.drums)])
            XCTAssertEqual(system.staves.map(\.showsRegionLabels), [true, false, false])
            XCTAssertTrue(system.staves.allSatisfy { staff in
                staff.system.viewportState.visibleMeasures.allSatisfy {
                    $0.attributes.clef == .treble
                }
            })

            let referenceMeasureNumbers = system.staves[0].system.viewportState.visibleMeasures.map(\.number)
            XCTAssertTrue(system.staves.dropFirst().allSatisfy {
                $0.system.viewportState.visibleMeasures.map(\.number) == referenceMeasureNumbers
            })
        }
    }

    func testLayoutKeepsTopRegionHostWhenMainPartIsHidden() {
        let layout = NotationWindowScoreLayout.make(
            partStates: [
                partState(part: .stem(.bass), currentTime: 1),
                partState(part: .stem(.drums), currentTime: 1)
            ],
            contentWidth: 1_000
        )

        XCTAssertEqual(layout.systems.first?.staves.map(\.part.id), [.stem(.bass), .stem(.drums)])
        XCTAssertEqual(layout.systems.first?.staves.map(\.showsRegionLabels), [true, false])
    }

    func testSinglePartLayoutUsesFullWidthAndStillShowsRegions() {
        let layout = NotationWindowScoreLayout.make(
            partStates: [partState(part: .stem(.bass), currentTime: 1)],
            contentWidth: 1_000
        )

        XCTAssertFalse(layout.usesPartGutter)
        XCTAssertEqual(layout.systems.first?.staves.map(\.showsRegionLabels), [true])
    }

    func testLayoutReflowChangesSignatureAndResolvesActiveSystem() {
        let partStates = [
            partState(part: .main, currentTime: 5.1),
            partState(part: .stem(.bass), currentTime: 5.1)
        ]
        let wideLayout = NotationWindowScoreLayout.make(
            partStates: partStates,
            contentWidth: 1_400
        )
        let narrowLayout = NotationWindowScoreLayout.make(
            partStates: partStates,
            contentWidth: 300
        )

        XCTAssertLessThan(narrowLayout.measuresPerSystem, wideLayout.measuresPerSystem)
        XCTAssertNotEqual(narrowLayout.signature, wideLayout.signature)
        XCTAssertNotNil(narrowLayout.activeSystemID)
        XCTAssertNotNil(wideLayout.activeSystemID)
        XCTAssertNotEqual(narrowLayout.activeSystemID, wideLayout.activeSystemID)
    }

    func testDenseMeasureOnlyReducesItsOwnSystemCapacity() {
        var main = partState(part: .main, currentTime: 1)
        main.scoreState.measures[0].notationItems = stride(
            from: 0.0,
            through: 3.75,
            by: 0.25
        ).enumerated().map { index, offset in
            NotationMeasureItem(
                id: "dense-window-\(index)",
                kind: .rest,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: offset,
                durationInQuarterNotes: 0.25,
                displayDuration: NotationDuration(denominator: 16)
            )
        }

        let layout = NotationWindowScoreLayout.make(
            partStates: [main],
            contentWidth: 720
        )
        let measureCounts = layout.systems.compactMap {
            $0.staves.first?.system.viewportState.visibleMeasures.count
        }

        XCTAssertEqual(measureCounts.first, 1)
        XCTAssertTrue(
            measureCounts.dropFirst().contains(AppTheme.NotationWindow.maximumMeasuresPerSystem)
        )
    }

    func testDenseSecondaryPartControlsSharedSystemBreaks() {
        let main = partState(part: .main, currentTime: 1)
        var bass = partState(part: .stem(.bass), currentTime: 1)
        bass.scoreState.measures[0].notationItems = stride(
            from: 0.0,
            through: 3.75,
            by: 0.25
        ).enumerated().map { index, offset in
            NotationMeasureItem(
                id: "dense-bass-\(index)",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 3),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: offset,
                durationInQuarterNotes: 0.25,
                displayDuration: NotationDuration(denominator: 16)
            )
        }

        let layout = NotationWindowScoreLayout.make(
            partStates: [main, bass],
            contentWidth: 720
        )

        XCTAssertEqual(systemMeasureCounts(in: layout).first, 1)
        for system in layout.systems {
            let referenceNumbers = system.staves[0].system.viewportState
                .visibleMeasures.map(\.number)
            XCTAssertTrue(system.staves.dropFirst().allSatisfy {
                $0.system.viewportState.visibleMeasures.map(\.number)
                    == referenceNumbers
            })
            XCTAssertTrue(system.staves.allSatisfy {
                system.measureLayout.matches(
                    $0.system.viewportState.visibleMeasures
                )
            })
        }
    }

    func testFiveMeasuresBalanceWithoutSingleMeasureSystem() {
        let layout = NotationWindowScoreLayout.make(
            partStates: [partState(part: .main, currentTime: 1, duration: 10)],
            contentWidth: 720
        )

        XCTAssertEqual(systemMeasureCounts(in: layout), [3, 2])
        assertOrderedMeasureCoverage(in: layout, expectedCount: 5)
    }

    func testSixMeasuresBalanceAcrossEqualSystems() {
        let layout = NotationWindowScoreLayout.make(
            partStates: [partState(part: .main, currentTime: 1, duration: 12)],
            contentWidth: 720
        )

        XCTAssertEqual(systemMeasureCounts(in: layout), [3, 3])
        assertOrderedMeasureCoverage(in: layout, expectedCount: 6)
    }

    func testElevenMeasuresDoNotLeaveLastMeasureAlone() {
        let layout = NotationWindowScoreLayout.make(
            partStates: [partState(part: .main, currentTime: 21, duration: 22)],
            contentWidth: 720
        )
        let counts = systemMeasureCounts(in: layout)

        XCTAssertEqual(counts.reduce(0, +), 11)
        XCTAssertFalse(counts.contains(1))
        XCTAssertEqual(counts, [4, 4, 3])
        assertOrderedMeasureCoverage(in: layout, expectedCount: 11)
    }

    func testScoreLayoutCacheReusesPlanWhenOnlyPlaybackAnchorChanges() {
        let cache = NotationWindowScoreLayoutCache()
        let initialStates = [partState(part: .main, currentTime: 1)]
        let initialLayout = cache.layout(
            partStates: initialStates,
            contentWidth: 720
        )
        var movedStates = initialStates
        movedStates[0].scoreState.anchorTime = 9
        movedStates[0].scoreState.activeMeasureNumber = 5
        let movedLayout = cache.layout(
            partStates: movedStates,
            contentWidth: 720
        )

        XCTAssertEqual(cache.cacheMissCount, 1)
        XCTAssertEqual(initialLayout.signature, movedLayout.signature)
        XCTAssertNotEqual(initialLayout.activeSystemID, movedLayout.activeSystemID)
        XCTAssertEqual(movedLayout.anchorTime, 9, accuracy: 0.0001)
    }

    func testScoreLayoutCacheInvalidatesForWidthPartsAndNotationContent() {
        let cache = NotationWindowScoreLayoutCache()
        let main = partState(part: .main, currentTime: 1)
        let initialLayout = cache.layout(
            partStates: [main],
            contentWidth: 720
        )
        let narrowLayout = cache.layout(
            partStates: [main],
            contentWidth: 300
        )
        let bass = partState(part: .stem(.bass), currentTime: 1)
        let multiPartLayout = cache.layout(
            partStates: [main, bass],
            contentWidth: 720
        )
        var denseBass = bass
        denseBass.scoreState.measures[0].notationItems = stride(
            from: 0.0,
            through: 3.75,
            by: 0.25
        ).enumerated().map { index, offset in
            NotationMeasureItem(
                id: "cache-bass-\(index)",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 3),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: offset,
                durationInQuarterNotes: 0.25,
                displayDuration: NotationDuration(denominator: 16)
            )
        }
        let denseLayout = cache.layout(
            partStates: [main, denseBass],
            contentWidth: 720
        )

        XCTAssertEqual(cache.cacheMissCount, 4)
        XCTAssertNotEqual(initialLayout.signature, narrowLayout.signature)
        XCTAssertFalse(narrowLayout.usesPartGutter)
        XCTAssertTrue(multiPartLayout.usesPartGutter)
        XCTAssertNotEqual(multiPartLayout.signature, denseLayout.signature)
    }

    private func systemMeasureCounts(
        in layout: NotationWindowScoreLayout
    ) -> [Int] {
        layout.systems.compactMap {
            $0.staves.first?.system.viewportState.visibleMeasures.count
        }
    }

    private func assertOrderedMeasureCoverage(
        in layout: NotationWindowScoreLayout,
        expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for partIndex in 0..<(layout.systems.first?.staves.count ?? 0) {
            let measureNumbers = layout.systems.flatMap {
                $0.staves[partIndex].system.viewportState.visibleMeasures.map(\.number)
            }
            XCTAssertEqual(
                measureNumbers,
                Array(1...expectedCount),
                file: file,
                line: line
            )
        }
    }

    private func partState(
        part: NotationPartDescriptor,
        currentTime: TimeInterval,
        duration: TimeInterval = 16
    ) -> NotationWindowPartRenderState {
        let tempoMap = TempoMap(
            baseSettings: BeatGridSettings(
                bpm: 120,
                firstBeatTime: 0,
                timeSignature: .fourFour
            ),
            markers: [],
            duration: duration
        )
        let scoreState = NotationViewportFactory().scoreState(
            tempoMap: tempoMap,
            duration: tempoMap.duration,
            currentTime: currentTime,
            playbackMarkerTime: 0,
            isPlaying: true,
            keyName: "C major",
            partID: part.id,
            includesHarmonies: part.id.isMain,
            notationItems: [],
            harmonySymbols: [],
            notes: [
                TimecodedNote(kind: .region, time: 0.5, duration: 3, title: "Intro")
            ]
        )
        return NotationWindowPartRenderState(part: part, scoreState: scoreState)
    }
}
