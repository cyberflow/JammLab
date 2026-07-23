import XCTest
@testable import JammLab
final class NotationBeamGeometryTests: XCTestCase {
    private let staffTop: CGFloat = 40
    private let staffSpace: CGFloat = 8

    func testTwoEqualEighthNotesProduceHorizontalPrimaryBeam() throws {
        let group = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [4, 4]
        )

        XCTAssertEqual(group.stemDirection, .up)
        XCTAssertEqual(
            group.primaryStartAnchor.y,
            group.primaryEndAnchor.y,
            accuracy: 0.0001
        )
        XCTAssertTrue(group.secondarySegments.isEmpty)
        XCTAssertEqual(group.primarySegment.polygonPoints.count, 4)
        assertMinimumStemLengths(group)
    }

    func testAscendingEighthNotesProduceRisingBeam() throws {
        let group = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [7, 5]
        )

        XCTAssertLessThan(
            group.primaryEndAnchor.y,
            group.primaryStartAnchor.y
        )
        assertMinimumStemLengths(group)
    }

    func testDescendingEighthNotesProduceFallingBeam() throws {
        let group = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [5, 7]
        )

        XCTAssertGreaterThan(
            group.primaryEndAnchor.y,
            group.primaryStartAnchor.y
        )
        assertMinimumStemLengths(group)
    }

    func testInternalHighNoteShiftsUpBeamWithoutChangingSlope() throws {
        let group = try onlyGroup(
            denominators: [16, 16, 8],
            staffPositions: [7, 2, 7]
        )

        XCTAssertEqual(
            group.primaryStartAnchor.y,
            group.primaryEndAnchor.y,
            accuracy: 0.0001
        )
        assertMinimumStemLengths(group)
    }

    func testInternalLowNoteShiftsDownBeamWithoutChangingSlope() throws {
        let group = try onlyGroup(
            denominators: [16, 16, 8],
            staffPositions: [0, 3, 0]
        )

        XCTAssertEqual(group.stemDirection, .down)
        XCTAssertEqual(
            group.primaryStartAnchor.y,
            group.primaryEndAnchor.y,
            accuracy: 0.0001
        )
        assertMinimumStemLengths(group)
    }

    func testFourSixteenthsHaveContinuousPrimaryAndSecondaryBeams() throws {
        let group = try onlyGroup(
            denominators: [16, 16, 16, 16],
            staffPositions: [5, 5, 5, 5]
        )

        XCTAssertEqual(group.beamLevelCount, 2)
        XCTAssertEqual(group.secondarySegments.count, 1)
        let secondary = try XCTUnwrap(group.secondarySegments.first)
        XCTAssertFalse(secondary.isBeamlet)
        XCTAssertEqual(
            secondary.start.x,
            try XCTUnwrap(group.notes.first).stemX,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            secondary.end.x,
            try XCTUnwrap(group.notes.last).stemX,
            accuracy: 0.0001
        )
    }

    func testTwoSixteenthsThenEighthHaveLeadingSecondarySegment() throws {
        let group = try onlyGroup(
            denominators: [16, 16, 8],
            staffPositions: [5, 5, 5]
        )
        let secondary = try XCTUnwrap(group.secondarySegments.first)

        XCTAssertEqual(group.secondarySegments.count, 1)
        XCTAssertFalse(secondary.isBeamlet)
        XCTAssertEqual(secondary.start.x, group.notes[0].stemX, accuracy: 0.0001)
        XCTAssertEqual(secondary.end.x, group.notes[1].stemX, accuracy: 0.0001)
    }

    func testEighthThenTwoSixteenthsHaveTrailingSecondarySegment() throws {
        let group = try onlyGroup(
            denominators: [8, 16, 16],
            staffPositions: [5, 5, 5]
        )
        let secondary = try XCTUnwrap(group.secondarySegments.first)

        XCTAssertEqual(group.secondarySegments.count, 1)
        XCTAssertFalse(secondary.isBeamlet)
        XCTAssertEqual(secondary.start.x, group.notes[1].stemX, accuracy: 0.0001)
        XCTAssertEqual(secondary.end.x, group.notes[2].stemX, accuracy: 0.0001)
    }

    func testSeparatedSixteenthsProduceTwoInwardBeamlets() throws {
        let group = try onlyGroup(
            denominators: [16, 8, 16],
            staffPositions: [5, 5, 5]
        )

        XCTAssertEqual(group.secondarySegments.count, 2)
        XCTAssertTrue(group.secondarySegments.allSatisfy(\.isBeamlet))
        XCTAssertGreaterThan(
            group.secondarySegments[0].end.x,
            group.secondarySegments[0].start.x
        )
        XCTAssertLessThan(
            group.secondarySegments[1].end.x,
            group.secondarySegments[1].start.x
        )
    }

    func testSameContourAboveAndBelowStaffUsesOppositeStemDirections() throws {
        let upperGroup = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [1, 2]
        )
        let lowerGroup = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [7, 8]
        )

        XCTAssertEqual(upperGroup.stemDirection, .down)
        XCTAssertEqual(lowerGroup.stemDirection, .up)
    }

    func testCompoundMeterBreaksSecondaryBeamAtEighthBoundaries() throws {
        let groups = fixedSpacingBeamGroups(
            denominators: Array(repeating: 16, count: 6),
            staffPositions: Array(repeating: 5, count: 6),
            timeSignature: timeSignature(beats: 6, unit: 8)
        )
        let group = try XCTUnwrap(groups.first)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(group.notes.count, 6)
        XCTAssertEqual(group.secondarySegments.count, 3)
        XCTAssertTrue(group.secondarySegments.allSatisfy { !$0.isBeamlet })
    }

    func testBeamedChordsChooseDirectionFromWholeGroupExtremes() throws {
        let items = [
            pitchedNote(id: "first-high", staffPosition: 0, offset: 0),
            pitchedNote(id: "first-low", staffPosition: 8, offset: 0),
            pitchedNote(id: "second-high", staffPosition: 1, offset: 0.5),
            pitchedNote(id: "second-low", staffPosition: 7, offset: 0.5)
        ]

        let group = try XCTUnwrap(
            trackLayoutBeamGroups(items: items, clef: .treble).first
        )

        XCTAssertEqual(group.notes.count, 2)
        XCTAssertEqual(group.notes.map { $0.members.count }, [2, 2])
        XCTAssertEqual(group.stemDirection, .down)
    }

    func testBeamMembersPreserveOrderIdentityAndDisplayDuration() throws {
        let items = [
            pitchedNote(id: "first-low", staffPosition: 8, offset: 0),
            pitchedNote(id: "first-high", staffPosition: 0, offset: 0),
            pitchedNote(id: "second", staffPosition: 5, offset: 0.5)
        ]

        let group = try XCTUnwrap(
            trackLayoutBeamGroups(items: items, clef: .treble).first
        )

        XCTAssertEqual(
            group.notes[0].members.map(\.itemID),
            ["first-high", "first-low"]
        )
        XCTAssertEqual(
            group.notes[0].members.map(\.displayDuration),
            Array(repeating: NotationDuration(denominator: 8), count: 2)
        )
        XCTAssertEqual(
            group.notes[0].members.map(\.id),
            group.notes[0].members.map(\.selection.id)
        )
    }

    func testGroupAndMemberSelectionResolutionRemainDistinct() throws {
        let group = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [5, 5]
        )
        let firstMember = try XCTUnwrap(group.notes.first?.members.first)
        let lastMember = try XCTUnwrap(group.notes.last?.members.first)

        XCTAssertTrue(
            NotationBeamSelectionResolver.containsMatch(
                lastMember.selection,
                in: group
            )
        )
        XCTAssertFalse(
            lastMember.selection.matches(firstMember.selection)
        )
    }

    func testDrumChordsKeepOpposingStemLanesInSeparateBeamGroups() {
        let items = [
            drumNote(id: "first-crash", midiNoteNumber: 49, offset: 0),
            drumNote(id: "first-bass", midiNoteNumber: 36, offset: 0),
            drumNote(id: "second-crash", midiNoteNumber: 49, offset: 0.5),
            drumNote(id: "second-bass", midiNoteNumber: 36, offset: 0.5)
        ]

        let groups = trackLayoutBeamGroups(items: items, clef: .drums)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.stemDirection)), [.up, .down])
        XCTAssertTrue(groups.allSatisfy { $0.notes.count == 2 })
        XCTAssertTrue(
            groups.allSatisfy {
                $0.notes.allSatisfy { $0.members.count == 1 }
            }
        )
    }

    func testSingleEighthDoesNotCreateBeamGroupAndKeepsFlagFallback() {
        XCTAssertTrue(
            fixedSpacingBeamGroups(
                denominators: [8],
                staffPositions: [5]
            ).isEmpty
        )
    }

    func testPitchChangeUpdatesGeometryButNotRhythmicMembership() throws {
        let original = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [6, 6]
        )
        let changed = try onlyGroup(
            denominators: [8, 8],
            staffPositions: [1, 6]
        )

        XCTAssertEqual(
            original.notes.map { $0.members.map(\.itemID) },
            changed.notes.map { $0.members.map(\.itemID) }
        )
        XCTAssertNotEqual(
            original.primaryStartAnchor.y,
            changed.primaryStartAnchor.y
        )
    }

    func testDurationChangeRebuildsNeighboringGroups() {
        var items = (0..<8).map { index in
            pitchedNote(
                id: "note-\(index)",
                staffPosition: 5,
                offset: Double(index) * 0.5
            )
        }
        let originalGroups = trackLayoutBeamGroups(
            items: items,
            clef: .treble
        )
        items[2].durationInQuarterNotes = 1
        items[2].displayDuration = NotationDuration(denominator: 4)
        let changedGroups = trackLayoutBeamGroups(
            items: items,
            clef: .treble
        )

        XCTAssertEqual(
            originalGroups.map(\.notationItemIDs),
            [
                Set(["note-0", "note-1"]),
                Set(["note-2", "note-3"]),
                Set(["note-4", "note-5"]),
                Set(["note-6", "note-7"])
            ]
        )
        XCTAssertEqual(
            changedGroups.map(\.notationItemIDs),
            [
                Set(["note-0", "note-1"]),
                Set(["note-4", "note-5"]),
                Set(["note-6", "note-7"])
            ]
        )
    }

    private func onlyGroup(
        denominators: [Int],
        staffPositions: [Int],
        timeSignature: TimeSignature = .fourFour
    ) throws -> NotationBeamGroup {
        let groups = fixedSpacingBeamGroups(
            denominators: denominators,
            staffPositions: staffPositions,
            timeSignature: timeSignature
        )
        XCTAssertEqual(groups.count, 1)
        return try XCTUnwrap(groups.first)
    }

    private func fixedSpacingBeamGroups(
        denominators: [Int],
        staffPositions: [Int],
        timeSignature: TimeSignature = .fourFour
    ) -> [NotationBeamGroup] {
        precondition(denominators.count == staffPositions.count)
        var offset = 0.0
        var items: [NotationMeasureItem] = []
        for index in denominators.indices {
            let duration = 4.0 / Double(denominators[index])
            items.append(NotationMeasureItem(
                id: "note-\(index)",
                kind: .note,
                pitch: NotationPitchMapper.pitch(
                    forStaffPosition: staffPositions[index],
                    keySignature: .cMajor
                ),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: offset,
                durationInQuarterNotes: duration,
                displayDuration: NotationDuration(
                    denominator: denominators[index]
                )
            ))
            offset += duration
        }
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: timeSignature,
                clef: .treble
            ),
            notationItems: items
        )
        let layoutItems = items.enumerated().map { index, item in
            NotationItemLayoutItem(
                measure: measure,
                notationItem: item,
                selection: NotationItemSelection(measure: measure, item: item),
                x: 20 + CGFloat(index) * 24,
                stemDirectionOverride: nil
            )
        }
        return NotationBeamLayout.groups(
            from: layoutItems,
            staffTop: staffTop,
            staffSpace: staffSpace
        )
    }

    private func trackLayoutBeamGroups(
        items: [NotationMeasureItem],
        clef: Clef
    ) -> [NotationBeamGroup] {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: .fourFour,
                clef: clef
            ),
            notationItems: items
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 240,
            contentStartX: 20,
            contentEndX: 220,
            staffStartX: 20,
            staffEndX: 220
        )
        let layoutItems = NotationTrackLayoutItems.notationItems(
            visibleMeasures: [measure],
            geometries: [geometry]
        )
        return NotationBeamLayout.groups(
            from: layoutItems,
            staffTop: staffTop,
            staffSpace: staffSpace
        )
    }

    private func pitchedNote(
        id: String,
        staffPosition: Int,
        offset: Double
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: NotationPitchMapper.pitch(
                forStaffPosition: staffPosition,
                keySignature: .cMajor
            ),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: 0.5,
            displayDuration: NotationDuration(denominator: 8)
        )
    }

    private func drumNote(
        id: String,
        midiNoteNumber: Int,
        offset: Double
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: NotationPitchMapper.pitch(
                forMIDINoteNumber: midiNoteNumber,
                keySignature: .cMajor
            ),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: 0.5,
            displayDuration: NotationDuration(denominator: 8)
        )
    }

    private func assertMinimumStemLengths(
        _ group: NotationBeamGroup,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let metrics = NotationBeamLayoutMetrics(staffSpace: staffSpace)
        for note in group.notes {
            let beamY = NotationBeamLayout.beamY(
                at: note.stemX,
                start: group.primaryStartAnchor,
                end: group.primaryEndAnchor
            )
            switch group.stemDirection {
            case .up:
                let highestHeadY = note.members.map(\.y).min() ?? 0
                let nearBeamEdgeY = beamY + metrics.beamThickness / 2
                XCTAssertGreaterThanOrEqual(
                    highestHeadY - nearBeamEdgeY,
                    metrics.minimumStemLength - 0.0001,
                    file: file,
                    line: line
                )
                XCTAssertLessThan(note.stemEndY, nearBeamEdgeY)
            case .down:
                let lowestHeadY = note.members.map(\.y).max() ?? 0
                let nearBeamEdgeY = beamY - metrics.beamThickness / 2
                XCTAssertGreaterThanOrEqual(
                    nearBeamEdgeY - lowestHeadY,
                    metrics.minimumStemLength - 0.0001,
                    file: file,
                    line: line
                )
                XCTAssertGreaterThan(note.stemEndY, nearBeamEdgeY)
            }
        }
    }
}

private func timeSignature(beats: Int, unit: Int) -> TimeSignature {
    TimeSignature(beatsPerBar: beats, beatUnit: unit)
}
