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

    private func partState(
        part: NotationPartDescriptor,
        currentTime: TimeInterval
    ) -> NotationWindowPartRenderState {
        let tempoMap = TempoMap(
            baseSettings: BeatGridSettings(
                bpm: 120,
                firstBeatTime: 0,
                timeSignature: .fourFour
            ),
            markers: [],
            duration: 16
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
