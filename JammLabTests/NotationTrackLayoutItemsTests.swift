import XCTest
@testable import JammLab

final class NotationTrackLayoutItemsTests: XCTestCase {
    func testNotationTrackTogglePresentationUsesConsistentIcons() {
        XCTAssertEqual(
            NotationTrackTogglePresentation.systemName(isCollapsed: true),
            "music.note.list"
        )
        XCTAssertEqual(
            NotationTrackTogglePresentation.systemName(isCollapsed: false),
            "music.note"
        )
    }

    func testTimelineNotationActionAdapterSuppressesOnlyStemHarmonyActions() {
        let recorder = TimelineNotationActionRecorder()
        let actions = timelineViewActions(recorder: recorder)
        let mainActions = actions.notationTrackActions(allowsHarmony: true)
        let stemActions = actions.notationTrackActions(allowsHarmony: false)
        let harmony = HarmonySymbol(
            time: 0,
            measureNumber: 1,
            offsetInQuarterNotes: 0,
            rawText: "C"
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble
        )
        let notePlacement = NotationNotePlacement(
            measure: measure,
            targetRestID: "rest",
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: NotationPitch(step: .c, octave: 4),
            x: 0,
            y: 0
        )
        let restPlacement = NotationRestPlacement(
            measure: measure,
            targetRestID: "rest",
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            x: 0
        )

        mainActions.selectHarmony(harmony.id)
        mainActions.saveHarmony(harmony)
        mainActions.deleteHarmony(harmony.id)
        _ = mainActions.adjacentHarmonyPlacement(0, .next)
        stemActions.selectHarmony(harmony.id)
        stemActions.saveHarmony(harmony)
        stemActions.deleteHarmony(harmony.id)
        _ = stemActions.adjacentHarmonyPlacement(0, .next)

        mainActions.selectMeasure(nil, false, .main)
        stemActions.selectMeasure(nil, false, .stem(.bass))
        mainActions.selectItem(nil, false)
        stemActions.selectItem(nil, false)
        mainActions.locatePlaybackMarkerExactly(1)
        stemActions.locatePlaybackMarkerExactly(2)
        XCTAssertTrue(mainActions.insertNotationNote(notePlacement))
        XCTAssertTrue(stemActions.insertNotationNote(notePlacement))
        XCTAssertTrue(mainActions.insertNotationRest(restPlacement))
        XCTAssertTrue(stemActions.insertNotationRest(restPlacement))
        XCTAssertTrue(mainActions.deleteSelectedNotationNote())
        XCTAssertTrue(stemActions.deleteSelectedNotationNote())
        mainActions.changeClef(.main, .bass)
        stemActions.changeClef(.stem(.bass), .bass)

        XCTAssertEqual(recorder.harmonyCallCount, 4)
        XCTAssertEqual(recorder.measureSelectionCount, 2)
        XCTAssertEqual(recorder.itemSelectionCount, 2)
        XCTAssertEqual(recorder.playbackLocationCount, 2)
        XCTAssertEqual(recorder.notationInsertionCount, 4)
        XCTAssertEqual(recorder.deleteNotationCount, 2)
        XCTAssertEqual(recorder.clefChanges.map(\.0), [.main, .stem(.bass)])
        XCTAssertEqual(recorder.clefChanges.map(\.1), [.bass, .bass])
    }

    func testSelectedMeasureIndicesOnlyMatchTheRenderedPart() {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble
        )
        let bassSelection = NotationMeasureSelection(
            measure: measure,
            partID: .stem(.bass)
        )

        XCTAssertEqual(
            NotationTrackLayoutItems.selectedMeasureIndices(
                visibleMeasures: [measure],
                selectedMeasures: [bassSelection],
                partID: .stem(.bass)
            ),
            [0]
        )
        XCTAssertTrue(
            NotationTrackLayoutItems.selectedMeasureIndices(
                visibleMeasures: [measure],
                selectedMeasures: [bassSelection],
                partID: .main
            ).isEmpty
        )

        let mainAccessibilityValue = NotationTrackAccessibility.value(
            visibleMeasures: [measure],
            keySignature: .cMajor,
            timeSignature: .fourFour,
            selectedMeasures: [bassSelection],
            partID: .main
        )
        let bassAccessibilityValue = NotationTrackAccessibility.value(
            visibleMeasures: [measure],
            keySignature: .cMajor,
            timeSignature: .fourFour,
            selectedMeasures: [bassSelection],
            partID: .stem(.bass)
        )

        XCTAssertFalse(mainAccessibilityValue.contains("selected measure"))
        XCTAssertTrue(bassAccessibilityValue.contains("selected measure 1"))
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
}

private final class TimelineNotationActionRecorder {
    var harmonyCallCount = 0
    var measureSelectionCount = 0
    var itemSelectionCount = 0
    var playbackLocationCount = 0
    var notationInsertionCount = 0
    var deleteNotationCount = 0
    var clefChanges: [(NotationPartID, Clef)] = []
}

private func timelineViewActions(
    recorder: TimelineNotationActionRecorder
) -> TimelineViewActions {
    TimelineViewActions(
        locatePlaybackMarker: { _ in },
        locatePlaybackMarkerExactly: { _ in recorder.playbackLocationCount += 1 },
        addNote: { _ in },
        selectHarmony: { _ in recorder.harmonyCallCount += 1 },
        selectNotationMeasure: { _, _, _ in recorder.measureSelectionCount += 1 },
        selectNotationItem: { _, _ in recorder.itemSelectionCount += 1 },
        saveHarmony: { _ in recorder.harmonyCallCount += 1 },
        deleteHarmony: { _ in recorder.harmonyCallCount += 1 },
        adjacentHarmonyPlacement: { _, _ in
            recorder.harmonyCallCount += 1
            return nil
        },
        addTempoTimeSignatureMarker: { _ in },
        editNote: { _ in },
        deleteNote: { _ in },
        noteColorChanged: { _, _ in },
        noteCustomColorChanged: { _, _ in },
        markerTimeChanged: { _, _ in },
        saveLoopRegion: {},
        selectRegion: { _ in },
        activateRegionAsLoop: { _ in },
        focusRegion: { _ in },
        regionRangeChanged: { _, _, _ in },
        loopStartChanged: { _ in },
        loopEndChanged: { _ in },
        loopRegionChanged: { _, _ in },
        timelineScroll: { _, _, _ in },
        mainTrackVolumeChanged: { _ in },
        notationTrackCollapsedChanged: { _ in },
        stemNotationTrackCollapsedChanged: { _, _ in },
        stemNoteDisplayModeToggled: { _ in },
        notationDurationChanged: { _ in },
        notationDurationDotToggled: {},
        notationNoteEntryModeToggled: {},
        notationRestEntryModeToggled: {},
        addTiedNotationNote: {},
        canInsertNotationNote: { _ in true },
        insertNotationNote: { _ in
            recorder.notationInsertionCount += 1
            return true
        },
        insertNotationRest: { _ in
            recorder.notationInsertionCount += 1
            return true
        },
        changeSelectedNotePitch: { _, _ in true },
        changeNotationClef: { recorder.clefChanges.append(($0, $1)) },
        auditionNotePitch: { _ in },
        deleteSelectedNotationNote: {
            recorder.deleteNotationCount += 1
            return true
        },
        showNotationWindow: {}
    )
}
