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

    func testInlineAccidentalsUseSeparateColumnsForAdjacentChordNotes() {
        let notes = [
            NotationMeasureItem(
                id: "c",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                explicitAccidental: .natural,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "d",
                kind: .note,
                pitch: NotationPitch(step: .d, octave: 4),
                explicitAccidental: .sharp,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: notes
        )
        let layoutItems = notes.map {
            NotationItemLayoutItem(
                measure: measure,
                notationItem: $0,
                selection: NotationItemSelection(measure: measure, item: $0),
                x: 100,
                stemDirectionOverride: nil
            )
        }

        let accidentals = NotationTrackLayoutItems.accidentals(from: layoutItems)

        XCTAssertEqual(accidentals.count, 2)
        XCTAssertEqual(Set(accidentals.map(\.accidental)), [.natural, .sharp])
        XCTAssertEqual(Set(accidentals.map(\.x)), [84, 91])

        let drumMeasure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: .fourFour,
                clef: .drums
            ),
            notationItems: [notes[0]]
        )
        let drumLayoutItem = NotationItemLayoutItem(
            measure: drumMeasure,
            notationItem: notes[0],
            selection: NotationItemSelection(measure: drumMeasure, item: notes[0]),
            x: 100,
            stemDirectionOverride: nil
        )
        XCTAssertTrue(NotationTrackLayoutItems.accidentals(from: [drumLayoutItem]).isEmpty)
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
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: NotationPitch(step: .c, octave: 4),
            x: 0,
            y: 0
        )
        let restPlacement = NotationRestPlacement(
            measure: measure,
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
        XCTAssertTrue(mainActions.deleteSelectedNotationMeasureContents())
        XCTAssertTrue(stemActions.deleteSelectedNotationMeasureContents())
        XCTAssertTrue(mainActions.deleteSelectedNotationNote())
        XCTAssertTrue(stemActions.deleteSelectedNotationNote())
        mainActions.changeClef(.main, .bass)
        stemActions.changeClef(.stem(.bass), .bass)

        XCTAssertEqual(recorder.harmonyCallCount, 4)
        XCTAssertEqual(recorder.measureSelectionCount, 2)
        XCTAssertEqual(recorder.itemSelectionCount, 2)
        XCTAssertEqual(recorder.playbackLocationCount, 2)
        XCTAssertEqual(recorder.notationInsertionCount, 4)
        XCTAssertEqual(recorder.deleteMeasureContentsCount, 2)
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

    func testChordLayoutOffsetsSecondsAndMixedDurationLanes() throws {
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 240,
            contentStartX: 20,
            contentEndX: 220,
            staffStartX: 20,
            staffEndX: 220
        )
        let items = [
            NotationMeasureItem(
                id: "c-quarter",
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "d-quarter",
                kind: .note,
                pitch: NotationPitch(step: .d, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "g-half",
                kind: .note,
                pitch: NotationPitch(step: .g, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: items
        )

        let layout = NotationTrackLayoutItems.notationItems(
            visibleMeasures: [measure],
            geometries: [geometry]
        )
        let xByID: [String: CGFloat] = Dictionary(
            uniqueKeysWithValues: layout.map { ($0.notationItem.id, $0.x) }
        )

        XCTAssertNotEqual(xByID["c-quarter"], xByID["d-quarter"])
        let chordGroups = NotationTrackLayoutItems.chordRenderGroups(from: layout)
        let quarterChord = try XCTUnwrap(chordGroups.first)
        XCTAssertEqual(Set(quarterChord.items.map { $0.notationItem.id }), ["c-quarter", "d-quarter"])
        XCTAssertEqual(quarterChord.duration, NotationDuration(denominator: 4))
        XCTAssertEqual(Set(quarterChord.items.compactMap(\.stemDirectionOverride)).count, 1)
        XCTAssertFalse(chordGroups.contains { group in
            group.items.contains { $0.notationItem.id == "g-half" }
        })
        let quarterHitFrames = quarterChord.items.map { item -> CGRect in
            let pitch = item.notationItem.pitch!
            let staffPosition = NotationPitchMapper.staffPosition(
                for: pitch,
                clef: measure.attributes.clef
            )
            let centerY = NotationNotePlacementResolver.yPosition(
                forStaffPosition: staffPosition,
                staffTop: 40
            )
            return CGRect(
                x: item.x - AppTheme.Timeline.notationNoteHitWidth / 2,
                y: centerY - AppTheme.Timeline.notationNoteHitHeight / 2,
                width: AppTheme.Timeline.notationNoteHitWidth,
                height: AppTheme.Timeline.notationNoteHitHeight
            )
        }
        XCTAssertEqual(quarterHitFrames.count, 2)
        XCTAssertFalse(quarterHitFrames[0].intersects(quarterHitFrames[1]))
        XCTAssertNotEqual(xByID["c-quarter"], xByID["g-half"])
        XCTAssertEqual(
            layout.filter { $0.notationItem.id != "g-half" }.compactMap {
                $0.stemDirectionOverride
            }.count,
            2
        )
    }

    func testDrumStemResolverUsesEmptySecondLineFromBottomAndExactInstrumentMap() {
        XCTAssertEqual(NotationDrumStemLayout.direction(forStaffPosition: 5), .up)
        XCTAssertNil(NotationDrumStemLayout.direction(forStaffPosition: 6))
        XCTAssertEqual(NotationDrumStemLayout.direction(forStaffPosition: 7), .down)
        XCTAssertEqual(NotationDrumStemLayout.direction(forMIDINoteNumber: 49), .up)
        XCTAssertEqual(NotationDrumStemLayout.direction(forMIDINoteNumber: 36), .down)
        XCTAssertNil(NotationDrumStemLayout.direction(forMIDINoteNumber: 43))
    }

    func testTwoVoiceDrumOnsetRendersSingletonsWithOppositeStems() throws {
        let measure = drumMeasure(items: [
            drumNote(id: "crash", midiNoteNumber: 49),
            drumNote(id: "bass", midiNoteNumber: 36)
        ])
        let layout = drumLayout(for: measure)
        let directionByID = Dictionary(
            uniqueKeysWithValues: layout.compactMap { item in
                item.stemDirectionOverride.map { (item.notationItem.id, $0) }
            }
        )

        XCTAssertEqual(directionByID["crash"], .up)
        XCTAssertEqual(directionByID["bass"], .down)
        XCTAssertTrue(NotationTrackLayoutItems.chordRenderGroups(from: layout).isEmpty)
    }

    func testFourNoteDrumOnsetCreatesIndependentSharedStemGroups() throws {
        let measure = drumMeasure(items: [
            drumNote(id: "crash", midiNoteNumber: 49),
            drumNote(id: "ride", midiNoteNumber: 51),
            drumNote(id: "bass", midiNoteNumber: 36),
            drumNote(id: "bass-2", midiNoteNumber: 35)
        ])
        let groups = NotationTrackLayoutItems.chordRenderGroups(
            from: drumLayout(for: measure)
        )
        let itemIDsByDirection = Dictionary(
            uniqueKeysWithValues: groups.map { group in
                (group.stemDirection, Set(group.items.map { $0.notationItem.id }))
            }
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(itemIDsByDirection[.up], ["crash", "ride"])
        XCTAssertEqual(itemIDsByDirection[.down], ["bass", "bass-2"])
    }

    func testSamePositionDrumAlternatesRemainOneSharedStemGroup() throws {
        let snare = drumNote(id: "snare", midiNoteNumber: 38)
        var crossStick = drumNote(id: "cross-stick", midiNoteNumber: 37)
        crossStick.tieTargetItemID = "cross-stick-target"
        let crossStickTarget = drumNote(
            id: "cross-stick-target",
            midiNoteNumber: 37,
            offset: 1
        )
        let measure = drumMeasure(items: [
            snare,
            crossStick,
            crossStickTarget
        ])
        let layout = drumLayout(for: measure)
        let groups = NotationTrackLayoutItems.chordRenderGroups(from: layout)
        let group = try XCTUnwrap(groups.first)
        let xByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.notationItem.id, $0.x) })
        let snareX = try XCTUnwrap(xByID["snare"])
        let crossStickX = try XCTUnwrap(xByID["cross-stick"])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(group.stemDirection, .up)
        XCTAssertEqual(Set(group.items.map { $0.notationItem.id }), ["snare", "cross-stick"])
        XCTAssertEqual(
            abs(snareX - crossStickX),
            AppTheme.Timeline.notationDuplicateNoteOffset,
            accuracy: 0.0001
        )
        XCTAssertFalse(CGRect(
            x: snareX - AppTheme.Timeline.notationNoteHitWidth / 2,
            y: 0,
            width: AppTheme.Timeline.notationNoteHitWidth,
            height: AppTheme.Timeline.notationNoteHitHeight
        ).intersects(CGRect(
            x: crossStickX - AppTheme.Timeline.notationNoteHitWidth / 2,
            y: 0,
            width: AppTheme.Timeline.notationNoteHitWidth,
            height: AppTheme.Timeline.notationNoteHitHeight
        )))

        let tie = try XCTUnwrap(NotationTrackLayoutItems.ties(
            visibleMeasures: [measure],
            geometries: [drumGeometry],
            connections: [NotationTieConnection(
                source: NotationTieEndpoint(
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    measureAttributes: measure.attributes,
                    item: crossStick
                ),
                target: NotationTieEndpoint(
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    measureAttributes: measure.attributes,
                    item: crossStickTarget
                )
            )],
            staffTop: 40
        ).first)
        XCTAssertEqual(
            tie.start.x,
            crossStickX + AppTheme.Timeline.notationTieNoteheadInset,
            accuracy: 0.0001
        )
    }

    func testPolyphonicDrumOnsetKeepsDurationLanesAndForcesSingletonDirections() throws {
        let measure = drumMeasure(items: [
            drumNote(id: "crash-quarter", midiNoteNumber: 49),
            drumNote(
                id: "bass-half",
                midiNoteNumber: 36,
                duration: 2,
                denominator: 2
            )
        ])
        let layout = drumLayout(for: measure)
        let itemByID = Dictionary(uniqueKeysWithValues: layout.map { ($0.notationItem.id, $0) })
        let crash = try XCTUnwrap(itemByID["crash-quarter"])
        let bass = try XCTUnwrap(itemByID["bass-half"])

        XCTAssertEqual(crash.stemDirectionOverride, .up)
        XCTAssertEqual(bass.stemDirectionOverride, .down)
        XCTAssertEqual(
            abs(crash.x - bass.x),
            AppTheme.Timeline.notationPolyphonicLaneSpacing,
            accuracy: 0.0001
        )
        XCTAssertTrue(NotationTrackLayoutItems.chordRenderGroups(from: layout).isEmpty)
    }

    func testMonophonicDrumNoteKeepsLegacyStemFallback() throws {
        let measure = drumMeasure(items: [
            drumNote(id: "crash", midiNoteNumber: 49)
        ])

        XCTAssertNil(try XCTUnwrap(drumLayout(for: measure).first).stemDirectionOverride)
        XCTAssertEqual(NotationStemDirection.direction(forStaffPosition: -2), .down)
    }

    func testDrumLaneWithUnsupportedTriggerUsesLegacyDirectionForEveryNote() throws {
        let measure = drumMeasure(items: [
            drumNote(id: "bass", midiNoteNumber: 36),
            drumNote(id: "unsupported", midiNoteNumber: 43)
        ])
        let layout = drumLayout(for: measure)
        let directionByID = Dictionary(
            uniqueKeysWithValues: layout.compactMap { item in
                item.stemDirectionOverride.map { (item.notationItem.id, $0) }
            }
        )

        XCTAssertEqual(directionByID.count, 2)
        XCTAssertEqual(directionByID["bass"], .up)
        XCTAssertEqual(directionByID["unsupported"], .up)
        XCTAssertEqual(NotationDrumStemLayout.direction(forMIDINoteNumber: 36), .down)
        XCTAssertNil(NotationDrumStemLayout.direction(forMIDINoteNumber: 43))
    }

    func testDrumTiePlacementFollowsPolyphonicStemDirection() throws {
        for scenario in [
            (midiNoteNumber: 49, companionMIDINoteNumber: 36, expected: NotationTiePlacement.below),
            (midiNoteNumber: 36, companionMIDINoteNumber: 49, expected: NotationTiePlacement.above)
        ] {
            var source = drumNote(id: "source", midiNoteNumber: scenario.midiNoteNumber)
            source.tieTargetItemID = "target"
            let target = drumNote(
                id: "target",
                midiNoteNumber: scenario.midiNoteNumber,
                offset: 1
            )
            let measure = drumMeasure(items: [
                source,
                drumNote(id: "companion", midiNoteNumber: scenario.companionMIDINoteNumber),
                target
            ])
            let connection = NotationTieConnection(
                source: NotationTieEndpoint(
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    measureAttributes: measure.attributes,
                    item: source
                ),
                target: NotationTieEndpoint(
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    measureAttributes: measure.attributes,
                    item: target
                )
            )
            let tie = try XCTUnwrap(NotationTrackLayoutItems.ties(
                visibleMeasures: [measure],
                geometries: [drumGeometry],
                connections: [connection],
                staffTop: 40
            ).first)

            XCTAssertEqual(tie.placement, scenario.expected)
        }
    }

    func testVisibleMonophonicTieSourceTakesPrecedenceOverTargetStemOverride() throws {
        var source = drumNote(id: "source", midiNoteNumber: 49)
        source.tieTargetItemID = "target"
        let target = drumNote(id: "target", midiNoteNumber: 49, offset: 1)
        let measure = drumMeasure(items: [
            source,
            target,
            drumNote(id: "target-companion", midiNoteNumber: 36, offset: 1)
        ])
        let layoutByID = Dictionary(
            uniqueKeysWithValues: drumLayout(for: measure).map { ($0.notationItem.id, $0) }
        )
        XCTAssertNil(try XCTUnwrap(layoutByID["source"]).stemDirectionOverride)
        XCTAssertEqual(try XCTUnwrap(layoutByID["source"]).effectiveStemDirection, .down)
        XCTAssertEqual(try XCTUnwrap(layoutByID["target"]).stemDirectionOverride, .up)

        let tie = try XCTUnwrap(NotationTrackLayoutItems.ties(
            visibleMeasures: [measure],
            geometries: [drumGeometry],
            connections: [NotationTieConnection(
                source: NotationTieEndpoint(
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    measureAttributes: measure.attributes,
                    item: source
                ),
                target: NotationTieEndpoint(
                    measureNumber: measure.number,
                    measureStartTime: measure.startTime,
                    measureAttributes: measure.attributes,
                    item: target
                )
            )],
            staffTop: 40
        ).first)

        XCTAssertEqual(tie.placement, .above)
    }

    func testOffSystemTieSourceUsesVisibleTargetStemDirection() throws {
        var source = drumNote(
            id: "source",
            midiNoteNumber: 49,
            offset: 3,
            measureNumber: 1,
            measureStartTime: 0
        )
        source.tieTargetItemID = "target"
        let target = drumNote(
            id: "target",
            midiNoteNumber: 49,
            offset: 1,
            measureNumber: 2,
            measureStartTime: 2
        )
        let visibleMeasure = drumMeasure(
            number: 2,
            startTime: 2,
            items: [
                target,
                drumNote(
                    id: "target-companion",
                    midiNoteNumber: 36,
                    offset: 1,
                    measureNumber: 2,
                    measureStartTime: 2
                )
            ]
        )
        let tie = try XCTUnwrap(NotationTrackLayoutItems.ties(
            visibleMeasures: [visibleMeasure],
            geometries: [drumGeometry],
            connections: [NotationTieConnection(
                source: NotationTieEndpoint(
                    measureNumber: 1,
                    measureStartTime: 0,
                    measureAttributes: visibleMeasure.attributes,
                    item: source
                ),
                target: NotationTieEndpoint(
                    measureNumber: 2,
                    measureStartTime: 2,
                    measureAttributes: visibleMeasure.attributes,
                    item: target
                )
            )],
            staffTop: 40
        ).first)

        XCTAssertEqual(tie.placement, .below)
    }

    private var drumGeometry: NotationMeasureCanvasGeometry {
        NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 240,
            contentStartX: 20,
            contentEndX: 220,
            staffStartX: 20,
            staffEndX: 220
        )
    }

    private func drumLayout(for measure: ScoreMeasure) -> [NotationItemLayoutItem] {
        NotationTrackLayoutItems.notationItems(
            visibleMeasures: [measure],
            geometries: [drumGeometry]
        )
    }

    private func drumMeasure(
        number: Int = 1,
        startTime: TimeInterval = 0,
        items: [NotationMeasureItem]
    ) -> ScoreMeasure {
        ScoreMeasure(
            number: number,
            startTime: startTime,
            endTime: startTime + 2,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: .fourFour,
                clef: .drums
            ),
            notationItems: items
        )
    }

    private func drumNote(
        id: String,
        midiNoteNumber: Int,
        offset: Double = 0,
        duration: Double = 1,
        denominator: Int = 4,
        measureNumber: Int = 1,
        measureStartTime: TimeInterval = 0
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: NotationPitchMapper.pitch(
                forMIDINoteNumber: midiNoteNumber,
                keySignature: .cMajor
            ),
            measureNumber: measureNumber,
            measureStartTime: measureStartTime,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: duration,
            displayDuration: NotationDuration(denominator: denominator)
        )
    }
}

private final class TimelineNotationActionRecorder {
    var harmonyCallCount = 0
    var measureSelectionCount = 0
    var itemSelectionCount = 0
    var playbackLocationCount = 0
    var notationInsertionCount = 0
    var deleteMeasureContentsCount = 0
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
        auditionNotePitch: { _, _ in },
        deleteSelectedNotationMeasureContents: {
            recorder.deleteMeasureContentsCount += 1
            return true
        },
        deleteSelectedNotationNote: {
            recorder.deleteNotationCount += 1
            return true
        },
        showNotationWindow: {}
    )
}
