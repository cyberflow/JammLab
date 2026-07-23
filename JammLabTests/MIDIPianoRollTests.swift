import CoreGraphics
import XCTest
@testable import JammLab

final class MIDIPianoRollTests: XCTestCase {
    func testPitchRowsCoverFullMIDIRangeAndRoundTripCoordinates() {
        XCTAssertEqual(MIDIPianoRollLayout.midiNoteNumber(atY: 0), 127)
        XCTAssertEqual(
            MIDIPianoRollLayout.midiNoteNumber(
                atY: MIDIPianoRollLayout.yPosition(forMIDINoteNumber: 60) + 1
            ),
            60
        )
        XCTAssertEqual(MIDIPianoRollLayout.pitchName(60), "C4")
        XCTAssertEqual(MIDIPianoRollLayout.pitchName(61, usesFlats: true), "D♭4")
        XCTAssertTrue(MIDIPianoRollLayout.isBlackKey(61))
        XCTAssertFalse(MIDIPianoRollLayout.isBlackKey(60))
    }

    func testMeasureCellsSnapToSixteenthGridAndMapPlayhead() throws {
        let measure = makeMeasure(number: 3, startTime: 4, endTime: 6)
        let cells = MIDIPianoRollLayout.measureCells(
            visibleMeasures: [measure],
            totalWidth: 440,
            pitchLabelWidth: 40
        )
        let cell = try XCTUnwrap(cells.first)

        XCTAssertEqual(cell.x, 40, accuracy: 0.0001)
        XCTAssertEqual(cell.width, 400, accuracy: 0.0001)
        XCTAssertEqual(
            MIDIPianoRollLayout.snappedQuarterOffset(atX: 171, cell: cell),
            1.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(MIDIPianoRollLayout.playheadX(anchorTime: 5, cells: cells)),
            240,
            accuracy: 0.0001
        )
    }

    func testNoteLayoutUsesDurationAndPitch() throws {
        let pitch = NotationPitch(step: .c, octave: 4)
        let note = NotationMeasureItem(
            id: "middle-c",
            kind: .note,
            pitch: pitch,
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        let layouts = MIDIPianoRollLayout.noteLayoutItems(
            visibleMeasures: [makeMeasure(notationItems: [note])],
            totalWidth: 440,
            noteInset: 1,
            rowHeight: 12
        )
        let layout = try XCTUnwrap(layouts.first)

        XCTAssertEqual(layout.rect.minX, 141, accuracy: 0.0001)
        XCTAssertEqual(layout.rect.width, 198, accuracy: 0.0001)
        XCTAssertEqual(layout.rect.minY, MIDIPianoRollLayout.yPosition(forMIDINoteNumber: 60) + 1)
    }

    func testPitchMapperUsesKeySpellingAndClefEditableRange() {
        XCTAssertEqual(
            NotationPitchMapper.pitch(forMIDINoteNumber: 61, keySignature: .cMajor),
            NotationPitch(step: .c, octave: 4, alter: 1)
        )
        XCTAssertEqual(
            NotationPitchMapper.pitch(
                forMIDINoteNumber: 61,
                keySignature: KeySignature(fifths: -1, mode: .major, displayName: "F major")
            ),
            NotationPitch(step: .d, octave: 4, alter: -1)
        )
        XCTAssertTrue(NotationPitchMapper.editableMIDINoteBounds(for: .treble).contains(60))
        XCTAssertFalse(NotationPitchMapper.editableMIDINoteBounds(for: .treble).contains(24))
        XCTAssertTrue(NotationPitchMapper.editableMIDINoteBounds(for: .bass).contains(40))
    }

    func testInsertionAtSnappedOffsetSplitsContainingRest() throws {
        let measure = makeMeasure(notationItems: [
            NotationMeasureItem(
                id: "whole-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 1),
                isSynthesized: true
            )
        ])
        let pitch = NotationPitch(step: .e, octave: 4)
        let placement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: measure,
            quarterOffset: 1.25,
            selectedDuration: NotationDuration(denominator: 4),
            pitch: pitch,
            partID: .main,
            x: 0,
            y: 0
        ))
        let plan = try XCTUnwrap(NotationNoteInsertionPlanner.planInsertion(
            in: [measure],
            placement: placement
        ))
        let items = try XCTUnwrap(plan.replacements.first).items
        let inserted = try XCTUnwrap(items.first { $0.kind == .note })

        XCTAssertEqual(inserted.offsetInQuarterNotes, 1.25, accuracy: 0.0001)
        XCTAssertEqual(inserted.durationInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(inserted.pitch, pitch)
        XCTAssertEqual(items.reduce(0) { $0 + $1.durationInQuarterNotes }, 4, accuracy: 0.0001)
        XCTAssertFalse(items.contains(where: \.isSynthesized))
        XCTAssertFalse(items.contains { item in
            item.id != inserted.id
                && item.offsetInQuarterNotes < 2.25
                && item.offsetInQuarterNotes + item.durationInQuarterNotes > 1.25
        })
    }

    func testExplicitPlacementRejectsPitchOutsideClefRange() {
        let measure = makeMeasure(notationItems: [
            NotationMeasureItem(
                id: "whole-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 1)
            )
        ])

        XCTAssertNil(NotationNotePlacementResolver.placement(
            in: measure,
            quarterOffset: 0,
            selectedDuration: NotationDuration(denominator: 4),
            pitch: NotationPitchMapper.pitch(forMIDINoteNumber: 0, keySignature: .cMajor),
            partID: .main,
            x: 0,
            y: 0
        ))
    }

    func testExplicitRestPlacementUsesContainingPartRest() throws {
        let stemPart = NotationPartID.stem(.bass)
        let measure = makeMeasure(notationItems: [
            NotationMeasureItem(
                id: "main-rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 1)
            ),
            NotationMeasureItem(
                id: "stem-rest",
                partID: stemPart,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 4,
                displayDuration: NotationDuration(denominator: 1)
            )
        ])
        let placement = try XCTUnwrap(NotationNotePlacementResolver.restPlacement(
            in: measure,
            quarterOffset: 1.25,
            selectedDuration: NotationDuration(denominator: 8),
            partID: stemPart,
            x: 100
        ))

        XCTAssertEqual(placement.partID, stemPart)
        XCTAssertEqual(placement.offsetInQuarterNotes, 1.25, accuracy: 0.0001)
        XCTAssertEqual(placement.durationInQuarterNotes, 0.5, accuracy: 0.0001)
    }

    func testEditHitDistinguishesBodyAndBothResizeEdges() throws {
        let note = makeNote(id: "editable", measureNumber: 1, measureStartTime: 0, offset: 1, duration: 1)
        let layout = try XCTUnwrap(MIDIPianoRollLayout.noteLayoutItems(
            visibleMeasures: [makeMeasure(notationItems: [note])],
            totalWidth: 440
        ).first)
        let geometries = MIDIPianoRollLayout.noteInteractionGeometries(
            layoutItems: [layout],
            tieConnections: []
        )

        XCTAssertEqual(
            MIDIPianoRollLayout.editHit(
                at: CGPoint(x: layout.rect.minX + 1, y: layout.rect.midY),
                geometries: geometries
            )?.mode,
            .leading
        )
        XCTAssertEqual(
            MIDIPianoRollLayout.editHit(
                at: CGPoint(x: layout.rect.midX, y: layout.rect.midY),
                geometries: geometries
            )?.mode,
            .body
        )
        XCTAssertEqual(
            MIDIPianoRollLayout.editHit(
                at: CGPoint(x: layout.rect.maxX - 1, y: layout.rect.midY),
                geometries: geometries
            )?.mode,
            .trailing
        )
    }

    func testInteractionGeometrySharesMinimumHitAreaAndTieResizePermissions() throws {
        let continuationID = "continuation"
        let root = makeNote(
            id: "root",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 3.75,
            duration: 0.25,
            tieTargetItemID: continuationID
        )
        let continuation = makeNote(
            id: continuationID,
            measureNumber: 2,
            measureStartTime: 2,
            offset: 0,
            duration: 0.25
        )
        let measures = [
            makeMeasure(number: 1, startTime: 0, endTime: 2, notationItems: [root]),
            makeMeasure(number: 2, startTime: 2, endTime: 4, notationItems: [continuation])
        ]
        let layouts = MIDIPianoRollLayout.noteLayoutItems(
            visibleMeasures: measures,
            totalWidth: 440
        )
        let geometries = MIDIPianoRollLayout.noteInteractionGeometries(
            layoutItems: layouts,
            tieConnections: NotationTieResolver.connections(in: measures)
        )
        let rootGeometry = try XCTUnwrap(geometries.first { $0.layoutItem.item.id == root.id })
        let continuationGeometry = try XCTUnwrap(
            geometries.first { $0.layoutItem.item.id == continuation.id }
        )

        XCTAssertGreaterThanOrEqual(
            rootGeometry.hitRect.width,
            AppTheme.Timeline.midiMinimumNoteHitWidth
        )
        XCTAssertGreaterThanOrEqual(
            rootGeometry.hitRect.height,
            AppTheme.Timeline.midiMinimumNoteHitHeight
        )
        XCTAssertTrue(rootGeometry.canResizeLeading)
        XCTAssertFalse(rootGeometry.canResizeTrailing)
        XCTAssertFalse(continuationGeometry.canResizeLeading)
        XCTAssertTrue(continuationGeometry.canResizeTrailing)
        XCTAssertEqual(
            rootGeometry.hitMode(at: CGPoint(
                x: rootGeometry.layoutItem.rect.maxX - 1,
                y: rootGeometry.hitRect.midY
            )),
            .body
        )
        XCTAssertEqual(
            continuationGeometry.hitMode(at: CGPoint(
                x: continuationGeometry.layoutItem.rect.minX + 1,
                y: continuationGeometry.hitRect.midY
            )),
            .body
        )
    }

    func testPlannerMovesNoteBySixteenthGridAndSemitoneWithoutChangingDuration() throws {
        let source = makeNote(
            id: "source",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 1,
            explicitAccidental: .natural
        )
        let measure = makeMeasure(notationItems: [source])
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 0.25),
                targetPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 1.5),
                semitoneDelta: 2
            )
        )

        let preview = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: request,
            audioDuration: 2
        ))
        let plan = try XCTUnwrap(preview.plan)
        let moved = try XCTUnwrap(preview.previewItems.first)

        XCTAssertEqual(moved.id, source.id)
        XCTAssertEqual(moved.offsetInQuarterNotes, 1.25, accuracy: 0.0001)
        XCTAssertEqual(moved.durationInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.pitch?.midiNoteNumber, 62)
        XCTAssertNil(moved.explicitAccidental)
        XCTAssertEqual(
            try XCTUnwrap(plan.replacements.first).items.reduce(0) { $0 + $1.durationInQuarterNotes },
            4,
            accuracy: 0.0001
        )
    }

    func testPlannerMovesExistingDottedSixteenthWithoutChangingDuration() throws {
        let source = NotationMeasureItem(
            id: "dotted-sixteenth",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 0.375,
            displayDuration: NotationDuration(denominator: 16, isDotted: true)
        )
        let measure = makeMeasure(notationItems: [source])
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 0),
                targetPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 0.25),
                semitoneDelta: 0
            )
        )

        let moved = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: request,
            audioDuration: 2
        )?.previewItems.first)

        XCTAssertEqual(moved.offsetInQuarterNotes, 0.25, accuracy: 0.0001)
        XCTAssertEqual(moved.durationInQuarterNotes, 0.375, accuracy: 0.0001)
        XCTAssertEqual(moved.displayDuration, NotationDuration(denominator: 16, isDotted: true))
    }

    func testPlannerRejectsMoveThatCreatesExactDuplicate() throws {
        let source = makeNote(id: "source", measureNumber: 1, measureStartTime: 0, offset: 0, duration: 1)
        let blocker = makeNote(id: "blocker", measureNumber: 1, measureStartTime: 0, offset: 2, duration: 1)
        let measure = makeMeasure(notationItems: [source, blocker])
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 0),
                targetPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 2),
                semitoneDelta: 0
            )
        )

        let preview = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: request,
            audioDuration: 2
        ))

        XCTAssertFalse(preview.isValid)
        XCTAssertEqual(preview.invalidReason, .duplicate)
        XCTAssertFalse(preview.previewItems.isEmpty)
    }

    func testPlannerResizesAcrossMeasureAsSingleTiedLogicalNote() throws {
        let source = makeNote(
            id: "root",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 1,
            duration: 1,
            explicitAccidental: .sharp
        )
        let first = makeMeasure(number: 1, startTime: 0, endTime: 2, notationItems: [source])
        let second = makeMeasure(number: 2, startTime: 2, endTime: 4)
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .resize(
                edge: .trailing,
                boundary: NotationGridPosition(measure: second, offsetInQuarterNotes: 2)
            )
        )

        let preview = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [first, second],
            request: request,
            audioDuration: 4
        ))
        let plan = try XCTUnwrap(preview.plan)

        XCTAssertEqual(preview.previewItems.count, 2)
        XCTAssertEqual(preview.previewItems.first?.id, source.id)
        XCTAssertEqual(preview.previewItems.map(\.durationInQuarterNotes).reduce(0, +), 5, accuracy: 0.0001)
        XCTAssertEqual(preview.previewItems.first?.tieTargetItemID, preview.previewItems.last?.id)
        XCTAssertNil(preview.previewItems.last?.tieTargetItemID)
        XCTAssertEqual(preview.previewItems.first?.explicitAccidental, .sharp)
        XCTAssertNil(preview.previewItems.last?.explicitAccidental)
        XCTAssertEqual(Set(plan.replacements.map(\.measureNumber)), Set([1, 2]))
    }

    func testPlannerSplitsDurationLongerThanWholeInsideLongMeasure() throws {
        let source = makeNote(id: "root", measureNumber: 1, measureStartTime: 0, offset: 0, duration: 1)
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 3,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: TimeSignature(beatsPerBar: 6, beatUnit: 4),
                clef: .treble
            ),
            notationItems: [source]
        )
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .resize(
                edge: .trailing,
                boundary: NotationGridPosition(measure: measure, offsetInQuarterNotes: 5)
            )
        )

        let items = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: request,
            audioDuration: 3
        )?.previewItems)

        XCTAssertEqual(items.map(\.durationInQuarterNotes), [4, 1])
        XCTAssertEqual(items.first?.tieTargetItemID, items.last?.id)
    }

    func testPlannerRepresentsFiveSixteenthsWithExactTiedDurations() throws {
        let source = makeNote(id: "root", measureNumber: 1, measureStartTime: 0, offset: 0, duration: 1)
        let measure = makeMeasure(notationItems: [source])
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .resize(
                edge: .trailing,
                boundary: NotationGridPosition(measure: measure, offsetInQuarterNotes: 1.25)
            )
        )

        let items = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: request,
            audioDuration: 2
        )?.previewItems)

        XCTAssertEqual(items.map(\.durationInQuarterNotes), [1, 0.25])
        XCTAssertEqual(items.first?.tieTargetItemID, items.last?.id)
    }

    func testPlannerLeadingResizeKeepsEndAndMovesStartOnGrid() throws {
        let source = makeNote(id: "root", measureNumber: 1, measureStartTime: 0, offset: 1, duration: 1)
        let measure = makeMeasure(notationItems: [source])
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .resize(
                edge: .leading,
                boundary: NotationGridPosition(measure: measure, offsetInQuarterNotes: 0.5)
            )
        )

        let items = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: request,
            audioDuration: 2
        )?.previewItems)

        XCTAssertEqual(items.first?.id, source.id)
        XCTAssertEqual(try XCTUnwrap(items.first).offsetInQuarterNotes, 0.5, accuracy: 0.0001)
        XCTAssertEqual(items.map(\.durationInQuarterNotes).reduce(0, +), 1.5, accuracy: 0.0001)
    }

    func testPlannerResolvesWholeTieChainFromContinuationAndKeepsRootID() throws {
        let continuationID = "continuation"
        let root = makeNote(
            id: "root",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 4,
            tieTargetItemID: continuationID
        )
        let continuation = makeNote(
            id: continuationID,
            measureNumber: 2,
            measureStartTime: 2,
            offset: 0,
            duration: 1
        )
        let first = makeMeasure(number: 1, startTime: 0, endTime: 2, notationItems: [root])
        let second = makeMeasure(number: 2, startTime: 2, endTime: 4, notationItems: [continuation])
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: continuation.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(measure: second, offsetInQuarterNotes: 0),
                targetPosition: NotationGridPosition(measure: second, offsetInQuarterNotes: 0.25),
                semitoneDelta: 0
            )
        )

        let preview = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [first, second],
            request: request,
            audioDuration: 4
        ))
        _ = try XCTUnwrap(preview.plan)

        XCTAssertEqual(preview.sourceItemIDs, Set([root.id, continuation.id]))
        XCTAssertEqual(preview.rootItemID, root.id)
        XCTAssertEqual(preview.previewItems.first?.id, root.id)
        XCTAssertEqual(
            try XCTUnwrap(preview.previewItems.first).offsetInQuarterNotes,
            0.25,
            accuracy: 0.0001
        )
    }

    func testPlannerChecksRealAudioBoundaryInsideLastScoreMeasure() throws {
        let source = makeNote(id: "source", measureNumber: 1, measureStartTime: 0, offset: 0, duration: 1)
        let first = makeMeasure(number: 1, startTime: 0, endTime: 2, notationItems: [source])
        let second = makeMeasure(number: 2, startTime: 2, endTime: 4)
        let request = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .resize(
                edge: .trailing,
                boundary: NotationGridPosition(measure: second, offsetInQuarterNotes: 3)
            )
        )

        let preview = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [first, second],
            request: request,
            audioDuration: 3
        ))

        XCTAssertFalse(preview.isValid)
        XCTAssertEqual(preview.invalidReason, .audioBoundary)
    }

    func testResizeAllowsAdjacencyAndOneGridStepOverlap() throws {
        let source = makeNote(
            id: "source",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 1,
            duration: 0.5
        )
        let blocker = makeNote(
            id: "blocker",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 2,
            duration: 1
        )
        let measure = makeMeasure(notationItems: [source, blocker])

        let adjacent = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .resize(
                edge: .trailing,
                boundary: NotationGridPosition(measure: measure, offsetInQuarterNotes: 2)
            )
        )
        let overlapping = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: source.id,
            operation: .resize(
                edge: .trailing,
                boundary: NotationGridPosition(measure: measure, offsetInQuarterNotes: 2.25)
            )
        )

        XCTAssertTrue(try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: adjacent,
            audioDuration: 2
        )).isValid)
        let overlapPreview = try XCTUnwrap(NotationNoteEditPlanner.preview(
            in: [measure],
            request: overlapping,
            audioDuration: 2
        ))
        XCTAssertTrue(overlapPreview.isValid)
        XCTAssertNil(overlapPreview.invalidReason)
    }

    func testLeadingResizeHonorsAdjacencyMinimumDurationAndCrossingBoundary() throws {
        let blocker = makeNote(
            id: "blocker",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 0.5
        )
        let source = makeNote(
            id: "source",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 1,
            duration: 1
        )
        let measure = makeMeasure(notationItems: [blocker, source])
        func preview(at offset: Double) throws -> NotationNoteEditPreview {
            try XCTUnwrap(NotationNoteEditPlanner.preview(
                in: [measure],
                request: NotationNoteEditRequest(
                    partID: .main,
                    sourceItemID: source.id,
                    operation: .resize(
                        edge: .leading,
                        boundary: NotationGridPosition(
                            measure: measure,
                            offsetInQuarterNotes: offset
                        )
                    )
                ),
                audioDuration: 2
            ))
        }

        XCTAssertTrue(try preview(at: 0.5).isValid)
        XCTAssertTrue(try preview(at: 0.25).isValid)
        XCTAssertTrue(try preview(at: 1.75).isValid)
        XCTAssertEqual(try preview(at: 2).invalidReason, .duration)
    }

    func testAutoPageTargetResolvesBothEdgesAndUnavailablePages() {
        XCTAssertEqual(
            MIDIPianoRollAutoPage.target(
                pointerX: AppTheme.Timeline.midiPitchLabelWidth,
                width: 500,
                previousPageStartTime: 2,
                nextPageStartTime: 8
            ),
            MIDIPianoRollAutoPageTarget(direction: .previous, startTime: 2)
        )
        XCTAssertEqual(
            MIDIPianoRollAutoPage.target(
                pointerX: 499,
                width: 500,
                previousPageStartTime: 2,
                nextPageStartTime: 8
            ),
            MIDIPianoRollAutoPageTarget(direction: .next, startTime: 8)
        )
        XCTAssertNil(MIDIPianoRollAutoPage.target(
            pointerX: 250,
            width: 500,
            previousPageStartTime: 2,
            nextPageStartTime: 8
        ))
        XCTAssertNil(MIDIPianoRollAutoPage.target(
            pointerX: 499,
            width: 500,
            previousPageStartTime: 2,
            nextPageStartTime: nil
        ))
    }

    @MainActor
    func testCancelledAutoPageTaskNeverInvokesLateCallback() async {
        let gate = MIDIAutoPageSleepGate()
        var didFire = false
        let task = MIDIPianoRollAutoPage.schedule(
            delayNanoseconds: 1,
            sleep: { _ in await gate.sleep() },
            action: { didFire = true }
        )
        await gate.waitUntilStarted()

        task.cancel()
        await gate.open()
        await task.value

        XCTAssertFalse(didFire)
    }

    @MainActor
    func testAutoPageTaskInvokesCallbackAfterInjectedDelay() async {
        let gate = MIDIAutoPageSleepGate()
        var pageStartTime: TimeInterval?
        let task = MIDIPianoRollAutoPage.schedule(
            delayNanoseconds: 1,
            sleep: { _ in await gate.sleep() },
            action: { pageStartTime = 8 }
        )
        await gate.waitUntilStarted()

        XCTAssertNil(pageStartTime)
        await gate.open()
        await task.value

        XCTAssertEqual(pageStartTime, 8)
    }

    @MainActor
    func testViewModelPreviewAndCommitKeepPlaybackMarkerAndUseOneUndoStep() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let partID = NotationPartID.stem(.bass)
        let source = makeNote(
            id: "source",
            partID: partID,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 1
        )
        viewModel.notationItems = [source]
        viewModel.playbackMarkerTime = 1.5
        let markerBefore = viewModel.playbackMarkerTime
        let itemsBefore = viewModel.notationItems
        let measure = try notationMeasure(1, in: viewModel, partID: partID)
        let request = NotationNoteEditRequest(
            partID: partID,
            sourceItemID: source.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 0),
                targetPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 1),
                semitoneDelta: 1
            )
        )

        _ = try XCTUnwrap(viewModel.previewNotationNoteEdit(request)?.plan)
        XCTAssertEqual(viewModel.notationItems, itemsBefore)
        XCTAssertEqual(viewModel.playbackMarkerTime, markerBefore, accuracy: 0.0001)

        XCTAssertTrue(viewModel.commitNotationNoteEdit(request))
        XCTAssertEqual(viewModel.playbackMarkerTime, markerBefore, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, source.id)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(viewModel.notationItems.first(where: { $0.id == source.id })?.offsetInQuarterNotes, 1)

        viewModel.undoLastEdit()
        XCTAssertEqual(viewModel.playbackMarkerTime, markerBefore, accuracy: 0.0001)
        XCTAssertEqual(viewModel.notationItems, itemsBefore)
        XCTAssertNil(viewModel.selectedNotationItem)
        XCTAssertTrue(undoManager.canRedo)
    }

    @MainActor
    func testPreparedSessionKeepsSamePartSnapshotAndUsesFreshContextForOtherPart() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let bassPart = NotationPartID.stem(.bass)
        let initialBass = makeNote(
            id: "initial-bass",
            partID: bassPart,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 1
        )
        viewModel.notationItems = [initialBass]
        let bassMeasure = try notationMeasure(1, in: viewModel, partID: bassPart)
        viewModel.beginNotationNoteEdit(partID: bassPart)
        XCTAssertEqual(viewModel.preparedNotationNoteEditSession?.partID, bassPart)

        let lateBass = makeNote(
            id: "late-bass",
            partID: bassPart,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 2,
            duration: 1
        )
        viewModel.notationItems.append(lateBass)
        let samePartRequest = NotationNoteEditRequest(
            partID: bassPart,
            sourceItemID: lateBass.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(
                    measure: bassMeasure,
                    offsetInQuarterNotes: 2
                ),
                targetPosition: NotationGridPosition(
                    measure: bassMeasure,
                    offsetInQuarterNotes: 2.25
                ),
                semitoneDelta: 0
            )
        )
        XCTAssertNil(viewModel.previewNotationNoteEdit(samePartRequest))

        let mainNote = makeNote(
            id: "main-note",
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 1
        )
        viewModel.notationItems.append(mainNote)
        let mainMeasure = try notationMeasure(1, in: viewModel)
        let crossPartRequest = NotationNoteEditRequest(
            partID: .main,
            sourceItemID: mainNote.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(
                    measure: mainMeasure,
                    offsetInQuarterNotes: 0
                ),
                targetPosition: NotationGridPosition(
                    measure: mainMeasure,
                    offsetInQuarterNotes: 1
                ),
                semitoneDelta: 0
            )
        )
        XCTAssertTrue(try XCTUnwrap(viewModel.previewNotationNoteEdit(crossPartRequest)).isValid)

        viewModel.endNotationNoteEdit()
        XCTAssertNil(viewModel.preparedNotationNoteEditSession)
    }

    @MainActor
    func testViewModelMovesNoteAcrossPagesAsOneUndoableEdit() throws {
        let viewModel = try loadedNotationViewModel(duration: 12)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let partID = NotationPartID.stem(.bass)
        let source = makeNote(
            id: "source",
            partID: partID,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 1,
            duration: 1
        )
        viewModel.notationItems = [source]
        viewModel.playbackMarkerTime = 1.5
        let itemsBefore = viewModel.notationItems
        let firstMeasure = try notationMeasure(1, in: viewModel, partID: partID)
        let thirdMeasure = try notationMeasure(3, in: viewModel, partID: partID)
        let request = NotationNoteEditRequest(
            partID: partID,
            sourceItemID: source.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(
                    measure: firstMeasure,
                    offsetInQuarterNotes: 1.25
                ),
                targetPosition: NotationGridPosition(
                    measure: thirdMeasure,
                    offsetInQuarterNotes: 0.5
                ),
                semitoneDelta: 3
            )
        )

        XCTAssertTrue(viewModel.commitNotationNoteEdit(request))
        let itemsAfterCommit = viewModel.notationItems
        let moved = try XCTUnwrap(itemsAfterCommit.first { $0.id == source.id })
        XCTAssertEqual(moved.measureNumber, 3)
        XCTAssertEqual(moved.offsetInQuarterNotes, 0.25, accuracy: 0.0001)
        XCTAssertEqual(moved.durationInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.pitch?.midiNoteNumber, 63)
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.5, accuracy: 0.0001)
        XCTAssertTrue(undoManager.canUndo)
        for measureNumber in [1, 3] {
            let measureItems = itemsAfterCommit.filter {
                $0.partID == partID && $0.measureNumber == measureNumber
            }
            XCTAssertEqual(
                measureItems.reduce(0) { $0 + $1.durationInQuarterNotes },
                4,
                accuracy: 0.0001
            )
        }

        viewModel.undoLastEdit()
        XCTAssertEqual(viewModel.notationItems, itemsBefore)
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.5, accuracy: 0.0001)
        XCTAssertTrue(undoManager.canRedo)

        viewModel.redoLastEdit()
        XCTAssertEqual(viewModel.notationItems, itemsAfterCommit)
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.5, accuracy: 0.0001)
    }

    @MainActor
    func testCrossPageMoveRejectsExactDuplicateWithoutUndo() throws {
        let viewModel = try loadedNotationViewModel(duration: 12)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let partID = NotationPartID.stem(.bass)
        let source = makeNote(
            id: "source",
            partID: partID,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 1,
            duration: 1
        )
        let blocker = makeNote(
            id: "blocker",
            partID: partID,
            measureNumber: 3,
            measureStartTime: 4,
            offset: 0.25,
            duration: 1
        )
        viewModel.notationItems = [source, blocker]
        let itemsBefore = viewModel.notationItems
        let firstMeasure = try notationMeasure(1, in: viewModel, partID: partID)
        let thirdMeasure = try notationMeasure(3, in: viewModel, partID: partID)
        let request = NotationNoteEditRequest(
            partID: partID,
            sourceItemID: source.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(
                    measure: firstMeasure,
                    offsetInQuarterNotes: 1.25
                ),
                targetPosition: NotationGridPosition(
                    measure: thirdMeasure,
                    offsetInQuarterNotes: 0.5
                ),
                semitoneDelta: 0
            )
        )

        let preview = try XCTUnwrap(viewModel.previewNotationNoteEdit(request))
        XCTAssertEqual(preview.invalidReason, .duplicate)
        XCTAssertFalse(viewModel.commitNotationNoteEdit(request))
        XCTAssertEqual(viewModel.notationItems, itemsBefore)
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testViewModelResizesTieFromContinuationAsOneUndoableEdit() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let partID = NotationPartID.stem(.bass)
        let continuationID = "continuation"
        let root = makeNote(
            id: "root",
            partID: partID,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 4,
            tieTargetItemID: continuationID
        )
        let continuation = makeNote(
            id: continuationID,
            partID: partID,
            measureNumber: 2,
            measureStartTime: 2,
            offset: 0,
            duration: 1
        )
        viewModel.notationItems = [root, continuation]
        viewModel.playbackMarkerTime = 1.25
        let itemsBefore = viewModel.notationItems
        let secondMeasure = try notationMeasure(2, in: viewModel, partID: partID)
        let request = NotationNoteEditRequest(
            partID: partID,
            sourceItemID: continuationID,
            operation: .resize(
                edge: .trailing,
                boundary: NotationGridPosition(
                    measure: secondMeasure,
                    offsetInQuarterNotes: 2
                )
            )
        )

        XCTAssertTrue(viewModel.commitNotationNoteEdit(request))
        let itemsAfterCommit = viewModel.notationItems
        let committed = viewModel.notationItems.filter { $0.kind == .note }
        XCTAssertEqual(committed.first?.id, root.id)
        XCTAssertEqual(committed.map(\.durationInQuarterNotes).reduce(0, +), 6, accuracy: 0.0001)
        XCTAssertEqual(committed.first?.tieTargetItemID, committed.last?.id)
        XCTAssertEqual(viewModel.selectedNotationItem?.itemID, root.id)
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.25, accuracy: 0.0001)

        viewModel.undoLastEdit()
        XCTAssertEqual(viewModel.notationItems, itemsBefore)
        XCTAssertNil(viewModel.selectedNotationItem)
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.25, accuracy: 0.0001)

        viewModel.redoLastEdit()
        XCTAssertEqual(viewModel.notationItems, itemsAfterCommit)
        XCTAssertEqual(viewModel.playbackMarkerTime, 1.25, accuracy: 0.0001)
    }

    @MainActor
    func testCommitRevalidatesPreparedPreviewAgainstNewCollision() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let partID = NotationPartID.stem(.bass)
        let source = makeNote(
            id: "source",
            partID: partID,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 0,
            duration: 1
        )
        viewModel.notationItems = [source]
        let measure = try notationMeasure(1, in: viewModel, partID: partID)
        let request = NotationNoteEditRequest(
            partID: partID,
            sourceItemID: source.id,
            operation: .move(
                grabbedPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 0),
                targetPosition: NotationGridPosition(measure: measure, offsetInQuarterNotes: 2),
                semitoneDelta: 0
            )
        )
        viewModel.beginNotationNoteEdit(partID: partID)
        XCTAssertTrue(try XCTUnwrap(viewModel.previewNotationNoteEdit(request)).isValid)

        let blocker = makeNote(
            id: "blocker",
            partID: partID,
            measureNumber: 1,
            measureStartTime: 0,
            offset: 2,
            duration: 1
        )
        viewModel.notationItems.append(blocker)
        let itemsBeforeCommit = viewModel.notationItems

        XCTAssertFalse(viewModel.commitNotationNoteEdit(request))
        XCTAssertEqual(viewModel.notationItems, itemsBeforeCommit)
        XCTAssertFalse(undoManager.canUndo)
        viewModel.endNotationNoteEdit()
    }

    func testDrumInstrumentMapUsesExactSupportedTriggersAndPresentations() throws {
        let expectedNames = [
            "Bass Drum", "Snare", "Closed Hi-Hat", "Open Hi-Hat",
            "Crash Cymbal", "Ride Cymbal", "High Tom", "Floor Tom",
            "Bass Drum 2", "Cross-stick", "Splash Cymbal", "Pedal Hi-Hat",
            "Crash Cymbal 2", "Ride Bell", "Low Tom", "China Cymbal"
        ]
        let expectedDisplayPitches = [
            NotationPitch(step: .f, octave: 4), NotationPitch(step: .c, octave: 5),
            NotationPitch(step: .g, octave: 5), NotationPitch(step: .g, octave: 5),
            NotationPitch(step: .a, octave: 5), NotationPitch(step: .f, octave: 5),
            NotationPitch(step: .e, octave: 5), NotationPitch(step: .a, octave: 4),
            NotationPitch(step: .e, octave: 4), NotationPitch(step: .c, octave: 5),
            NotationPitch(step: .c, octave: 6), NotationPitch(step: .d, octave: 4),
            NotationPitch(step: .b, octave: 5), NotationPitch(step: .f, octave: 5),
            NotationPitch(step: .d, octave: 5), NotationPitch(step: .b, octave: 5)
        ]
        XCTAssertEqual(
            DrumInstrumentMap.instruments.map(\.midiNoteNumber),
            [36, 38, 42, 46, 49, 51, 50, 41, 35, 37, 55, 44, 57, 53, 47, 52]
        )
        XCTAssertEqual(DrumInstrumentMap.instruments.map(\.name), expectedNames)
        XCTAssertEqual(DrumInstrumentMap.instruments.map(\.displayPitch), expectedDisplayPitches)
        XCTAssertEqual(
            DrumInstrumentMap.instruments.map(\.staffPosition),
            [7, 3, -1, -1, -2, 0, 1, 5, 8, 3, -4, 9, -3, 0, 2, -3]
        )
        XCTAssertEqual(
            DrumInstrumentMap.instruments.map(\.noteheadStyle),
            [.normal, .normal, .x, .circleX, .x, .x, .normal, .normal,
             .normal, .x, .x, .x, .x, .x, .normal, .x]
        )
        XCTAssertEqual(
            DrumInstrumentMap.instruments.map(\.isPrimaryAtPosition),
            [true, true, true, false, true, true, true, true,
             true, false, true, true, true, false, true, false]
        )
        XCTAssertEqual(DrumInstrumentMap.allowedMIDINoteNumbers.count, 16)

        let snare = try XCTUnwrap(DrumInstrumentMap.instrument(forMIDINoteNumber: 38))
        let crossStick = try XCTUnwrap(DrumInstrumentMap.instrument(forMIDINoteNumber: 37))
        let openHiHat = try XCTUnwrap(DrumInstrumentMap.instrument(forMIDINoteNumber: 46))
        XCTAssertEqual(snare.staffPosition, 3)
        XCTAssertEqual(snare.noteheadStyle, .normal)
        XCTAssertEqual(crossStick.staffPosition, snare.staffPosition)
        XCTAssertEqual(crossStick.noteheadStyle, .x)
        XCTAssertEqual(openHiHat.noteheadStyle, .circleX)
        XCTAssertNil(DrumInstrumentMap.instrument(forMIDINoteNumber: 43))
        XCTAssertFalse(DrumInstrumentMap.instruments.contains {
            $0.staffPosition == NotationDrumStemLayout.emptyStaffPosition
        })
        XCTAssertEqual(
            DrumInstrumentMap.instrument(forMIDINoteNumber: 47)?.staffPosition,
            2
        )
    }

    func testDrumInstrumentMapNavigationPreservesStaffOrderAndTieBreaks() throws {
        let pedalHiHat = try XCTUnwrap(DrumInstrumentMap.instrument(forMIDINoteNumber: 44))
        let splash = try XCTUnwrap(DrumInstrumentMap.instrument(forMIDINoteNumber: 55))
        let openHiHat = try XCTUnwrap(DrumInstrumentMap.instrument(forMIDINoteNumber: 46))

        XCTAssertEqual(
            DrumInstrumentMap.nearestPrimaryInstrument(forStaffPosition: 4).midiNoteNumber,
            41
        )
        XCTAssertEqual(
            DrumInstrumentMap.adjacentPrimaryInstrument(
                from: openHiHat,
                staffPositionDelta: 1
            )?.midiNoteNumber,
            51
        )
        XCTAssertEqual(
            DrumInstrumentMap.adjacentPrimaryInstrument(
                from: openHiHat,
                staffPositionDelta: -1
            )?.midiNoteNumber,
            49
        )
        XCTAssertNil(DrumInstrumentMap.adjacentPrimaryInstrument(
            from: pedalHiHat,
            staffPositionDelta: 1
        ))
        XCTAssertNil(DrumInstrumentMap.adjacentPrimaryInstrument(
            from: splash,
            staffPositionDelta: -1
        ))
        XCTAssertNil(DrumInstrumentMap.adjacentPrimaryInstrument(
            from: openHiHat,
            staffPositionDelta: 0
        ))
    }

    func testDrumInputPolicyRejectsNotesBetweenSupportedTriggers() {
        XCTAssertEqual(NotationPitchMapper.editableMIDINoteBounds(for: .drums), 35...57)
        for midiNoteNumber in 0...127 {
            XCTAssertEqual(
                NotationInputPolicy.isEditableMIDINoteNumber(midiNoteNumber, in: .drums),
                DrumInstrumentMap.allowedMIDINoteNumbers.contains(midiNoteNumber)
            )
        }
        XCTAssertFalse(NotationInputPolicy.isEditableMIDINoteNumber(40, in: .drums))
    }

    func testDrumInsertionPlannerRejectsUnsupportedTriggerEvenWithExplicitPlacement() {
        let measure = makeMeasure(
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: .fourFour,
                clef: .drums
            ),
            notationItems: [
                NotationMeasureItem(
                    id: "whole-rest",
                    partID: .stem(.drums),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 4,
                    displayDuration: NotationDuration(denominator: 1)
                )
            ]
        )
        let placement = NotationNotePlacement(
            measure: measure,
            partID: .stem(.drums),
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            pitch: NotationPitchMapper.pitch(forMIDINoteNumber: 40, keySignature: .cMajor),
            x: 0,
            y: 0
        )

        XCTAssertFalse(NotationNoteInsertionPlanner.canPlanInsertion(in: [measure], placement: placement))
        XCTAssertNil(NotationNoteInsertionPlanner.planInsertion(in: [measure], placement: placement))
    }

    func testDrumNotationPlacementUsesSelectedInstrumentInsteadOfPointerHeight() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: .fourFour,
                clef: .drums
            )
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 400,
            contentStartX: 0,
            contentEndX: 400,
            staffStartX: 0,
            staffEndX: 400
        )
        let placement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: 100, y: 1_000),
            staffTop: 40,
            selectedDuration: NotationDuration(denominator: 4),
            partID: .stem(.drums),
            selectedDrumInstrumentMIDINoteNumber: 46
        ))

        XCTAssertEqual(placement.pitch.midiNoteNumber, 46)
        XCTAssertEqual(
            placement.y,
            NotationNotePlacementResolver.yPosition(forStaffPosition: -1, staffTop: 40),
            accuracy: 0.0001
        )
    }

    func testDrumClefIsDefaultForNewDrumPartsAndLegacyEvidenceRestoresTreble() {
        let partID = NotationPartID.stem(.drums)
        XCTAssertEqual(NotationPartClefOverrides.defaultClef(for: partID), .drums)
        XCTAssertEqual(NotationPartClefOverrides.clef(for: partID, in: [:]), .drums)

        let legacy = NotationPartClefOverrides.restored(
            [:],
            projectFormatVersion: 13,
            hasLegacyDrumNotationEvidence: true
        )
        XCTAssertEqual(legacy[partID], .treble)

        let modern = NotationPartClefOverrides.restored(
            [:],
            projectFormatVersion: 14,
            hasLegacyDrumNotationEvidence: true
        )
        XCTAssertNil(modern[partID])
    }

    private func makeMeasure(
        number: Int = 1,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 2,
        attributes: MeasureAttributes = .defaultTreble,
        notationItems: [NotationMeasureItem] = []
    ) -> ScoreMeasure {
        ScoreMeasure(
            number: number,
            startTime: startTime,
            endTime: endTime,
            attributes: attributes,
            notationItems: notationItems
        )
    }

    private func makeNote(
        id: String,
        partID: NotationPartID = .main,
        measureNumber: Int,
        measureStartTime: TimeInterval,
        offset: Double,
        duration: Double,
        midiNoteNumber: Int = 60,
        explicitAccidental: NotationAccidental? = nil,
        tieTargetItemID: String? = nil
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            partID: partID,
            kind: .note,
            pitch: NotationPitchMapper.pitch(forMIDINoteNumber: midiNoteNumber, keySignature: .cMajor),
            explicitAccidental: explicitAccidental,
            measureNumber: measureNumber,
            measureStartTime: measureStartTime,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: duration,
            displayDuration: NotationDuration(denominator: duration >= 1 ? 4 : 16),
            tieTargetItemID: tieTargetItemID
        )
    }
}

private actor MIDIAutoPageSleepGate {
    private var isStarted = false
    private var sleepContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        isStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            sleepContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func open() {
        sleepContinuation?.resume()
        sleepContinuation = nil
    }
}
