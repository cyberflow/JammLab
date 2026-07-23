import CoreGraphics
import XCTest
@testable import JammLab

final class NotationPrimitivesTests: XCTestCase {
    private let directionalStaffSymbolExpectations: [(
        denominator: Int,
        up: NotationStaffNoteSymbol,
        down: NotationStaffNoteSymbol,
        upCodepoint: UInt32,
        downCodepoint: UInt32
    )] = [
        (2, .half(.up), .half(.down), 0xE1D3, 0xE1D4),
        (4, .quarter(.up), .quarter(.down), 0xE1D5, 0xE1D6),
        (8, .eighth(.up), .eighth(.down), 0xE1D7, 0xE1D8),
        (16, .sixteenth(.up), .sixteenth(.down), 0xE1D9, 0xE1DA),
        (32, .thirtySecond(.up), .thirtySecond(.down), 0xE1DB, 0xE1DC)
    ]

    private var allStaffNoteSymbols: [NotationStaffNoteSymbol] {
        [.whole] + directionalStaffSymbolExpectations.flatMap { [$0.up, $0.down] }
    }

    func testNotationItemSelectionMatchingUsesTimingTolerance() {
        let item = NotationMeasureItem(
            id: "selection-note",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0.5,
            durationInQuarterNotes: 0.5,
            displayDuration: NotationDuration(denominator: 8)
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [item]
        )
        let candidate = NotationItemSelection(measure: measure, item: item)
        var selected = candidate
        selected.offsetInQuarterNotes +=
            NotationMeasureTiming.timelineTolerance / 2

        XCTAssertTrue(selected.matches(candidate))
    }

    func testNotationPartDescriptorsProvideMusicXMLMetadata() {
        let descriptors: [(NotationPartDescriptor, String, String, String?)] = [
            (.main, "Main", "Main", nil),
            (.stem(.vocals), "Vocals", "Voc.", "voice.vocals"),
            (.stem(.instrumental), "Instrumental", "Instr.", nil),
            (.stem(.drums), "Drum Set", "Dr.", "drum.group.set"),
            (.stem(.bass), "Bass Guitar", "B. Guit.", "pluck.bass"),
            (.stem(.other), "Other", "Other", nil),
            (.stem(.guitar), "Guitar", "Guit.", "pluck.guitar"),
            (.stem(.piano), "Piano", "Pno.", "keyboard.piano")
        ]

        for (descriptor, title, abbreviation, instrumentSound) in descriptors {
            XCTAssertEqual(descriptor.title, title)
            XCTAssertEqual(descriptor.abbreviation, abbreviation)
            XCTAssertEqual(descriptor.instrumentName, title)
            XCTAssertEqual(descriptor.instrumentSound, instrumentSound)
        }
    }

    func testNotationSMuFLRestSymbolsMapDurationsToCodepoints() throws {
        let whole = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 1)))
        let half = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 2)))
        let quarter = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 4)))
        let eighth = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 8)))
        let sixteenth = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 16)))
        let thirtySecond = try XCTUnwrap(NotationSMuFLSymbol(duration: NotationDuration(denominator: 32)))

        XCTAssertEqual(whole, .restWhole)
        XCTAssertEqual(whole.codepoint, 0xE4E3)
        XCTAssertEqual(half, .restHalf)
        XCTAssertEqual(half.codepoint, 0xE4E4)
        XCTAssertEqual(quarter, .restQuarter)
        XCTAssertEqual(quarter.codepoint, 0xE4E5)
        XCTAssertEqual(eighth, .rest8th)
        XCTAssertEqual(eighth.codepoint, 0xE4E6)
        XCTAssertEqual(sixteenth, .rest16th)
        XCTAssertEqual(sixteenth.codepoint, 0xE4E7)
        XCTAssertEqual(thirtySecond, .rest32nd)
        XCTAssertEqual(thirtySecond.codepoint, 0xE4E8)
        XCTAssertEqual(quarter.glyph.unicodeScalars.first?.value, 0xE4E5)
        XCTAssertEqual(NotationAugmentationDotSymbol.augmentationDot.codepoint, 0xE1E7)
    }

    func testNotationClefSymbolsUseLelandSMuFLCodepointsAndReferenceLines() {
        let treble = NotationClefSymbol(.treble)
        let bass = NotationClefSymbol(.bass)
        let drums = NotationClefSymbol(.drums)

        XCTAssertEqual(treble.codepoint, 0xE050)
        XCTAssertEqual(treble.referenceStaffLineFromTop, 3)
        XCTAssertEqual(bass.codepoint, 0xE062)
        XCTAssertEqual(bass.referenceStaffLineFromTop, 1)
        XCTAssertEqual(drums.codepoint, 0xE069)
        XCTAssertEqual(drums.referenceStaffLineFromTop, 2)
        XCTAssertEqual(Clef.treble.sign, "G")
        XCTAssertEqual(Clef.treble.line, 2)
        XCTAssertEqual(Clef.bass.sign, "F")
        XCTAssertEqual(Clef.bass.line, 4)
        XCTAssertEqual(Clef.drums.sign, "percussion")
        XCTAssertNil(Clef.drums.line)
    }

    func testNotationPartClefOverridesRemovePerPartDefaultValues() {
        let unknownPart = NotationPartID(rawValue: "future:baritone")
        let normalized = NotationPartClefOverrides.normalized([
            .main: .treble,
            .stem(.bass): .bass,
            .stem(.drums): .drums,
            unknownPart: .bass
        ])

        XCTAssertEqual(normalized, [
            .stem(.bass): .bass,
            unknownPart: .bass
        ])
        XCTAssertEqual(NotationPartClefOverrides.clef(for: .main, in: normalized), .treble)
        XCTAssertEqual(NotationPartClefOverrides.clef(for: .stem(.drums), in: normalized), .drums)
        XCTAssertEqual(NotationPartClefOverrides.clef(for: unknownPart, in: normalized), .bass)
    }

    func testNotationSMuFLDurationControlSymbolsMapDurationsToLelandMetNoteCodepoints() throws {
        let whole = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 1)))
        let half = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 2)))
        let quarter = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 4)))
        let eighth = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 8)))
        let sixteenth = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 16)))

        XCTAssertEqual(whole, .whole)
        XCTAssertEqual(whole.codepoint, 0xECA2)
        XCTAssertEqual(half, .half)
        XCTAssertEqual(half.codepoint, 0xECA3)
        XCTAssertEqual(quarter, .quarter)
        XCTAssertEqual(quarter.codepoint, 0xECA5)
        XCTAssertEqual(eighth, .eighth)
        XCTAssertEqual(eighth.codepoint, 0xECA7)
        XCTAssertEqual(sixteenth, .sixteenth)
        XCTAssertEqual(sixteenth.codepoint, 0xECA9)
        XCTAssertEqual(eighth.glyph.unicodeScalars.first?.value, 0xECA7)
    }

    func testNotationStaffNoteSymbolsUseDirectionSpecificLelandCodepoints() throws {
        let whole = try XCTUnwrap(NotationStaffNoteSymbol(duration: NotationDuration(denominator: 1)))
        let wholeWithDownDirection = try XCTUnwrap(NotationStaffNoteSymbol(
            duration: NotationDuration(denominator: 1),
            stemDirection: .down
        ))

        XCTAssertEqual(whole, .whole)
        XCTAssertEqual(wholeWithDownDirection, .whole)
        XCTAssertEqual(whole.codepoint, 0xE1D2)
        for expectation in directionalStaffSymbolExpectations {
            let duration = NotationDuration(denominator: expectation.denominator)
            let up = try XCTUnwrap(NotationStaffNoteSymbol(duration: duration, stemDirection: .up))
            let down = try XCTUnwrap(NotationStaffNoteSymbol(duration: duration, stemDirection: .down))
            XCTAssertEqual(up, expectation.up)
            XCTAssertEqual(down, expectation.down)
            XCTAssertEqual(up.codepoint, expectation.upCodepoint)
            XCTAssertEqual(down.codepoint, expectation.downCodepoint)
        }
    }

    func testChordPrimitivesUseStandaloneNoteheadsAndDirectionalFlags() {
        XCTAssertEqual(NotationNoteheadSymbol(duration: NotationDuration(denominator: 1)).codepoint, 0xE0A2)
        XCTAssertEqual(NotationNoteheadSymbol(duration: NotationDuration(denominator: 2)).codepoint, 0xE0A3)
        XCTAssertEqual(NotationNoteheadSymbol(duration: NotationDuration(denominator: 4)).codepoint, 0xE0A4)
        XCTAssertEqual(NotationDrumNoteheadSymbol.x.codepoint, 0xE0A9)
        XCTAssertEqual(NotationDrumNoteheadSymbol.circleX.codepoint, 0xE0B3)
        XCTAssertEqual(
            NotationFlagSymbol(
                duration: NotationDuration(denominator: 8),
                stemDirection: .up
            )?.codepoint,
            0xE240
        )
        XCTAssertEqual(
            NotationFlagSymbol(
                duration: NotationDuration(denominator: 16),
                stemDirection: .down
            )?.codepoint,
            0xE243
        )
        XCTAssertNil(NotationFlagSymbol(
            duration: NotationDuration(denominator: 4),
            stemDirection: .up
        ))
    }

    func testLelandFlagsAttachGlyphOriginToStemAndExtendInExpectedDirection() throws {
        let fontSize: CGFloat = 32.5
        let attachmentPoint = CGPoint(x: 42, y: 73)
        let symbols: [(symbol: NotationFlagSymbol, direction: NotationStemDirection)] = [
            (.eighth(.up), .up),
            (.eighth(.down), .down),
            (.sixteenth(.up), .up),
            (.sixteenth(.down), .down),
            (.thirtySecond(.up), .up),
            (.thirtySecond(.down), .down)
        ]

        for expectation in symbols {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: expectation.symbol,
                fontSize: fontSize
            ))
            let transform = NotationFlagLayout.transform(
                for: glyphPath,
                attachmentPoint: attachmentPoint
            )
            let transformedAttachment = NotationFlagLayout.attachmentAnchor.applying(transform)
            let transformedBounds = glyphPath.bounds.applying(transform)

            XCTAssertEqual(transformedAttachment.x, attachmentPoint.x, accuracy: 0.0001)
            XCTAssertEqual(transformedAttachment.y, attachmentPoint.y, accuracy: 0.0001)
            XCTAssertEqual(transformedBounds.minX, attachmentPoint.x, accuracy: 0.0001)
            XCTAssertTrue(transformedBounds.minY...transformedBounds.maxY ~= attachmentPoint.y)

            let upwardExtent = attachmentPoint.y - transformedBounds.minY
            let downwardExtent = transformedBounds.maxY - attachmentPoint.y
            if expectation.direction == .up {
                XCTAssertGreaterThan(downwardExtent, upwardExtent)
            } else {
                XCTAssertGreaterThan(upwardExtent, downwardExtent)
            }
        }
    }

    func testNotationStemDirectionChangesOnlyAboveMiddleStaffLine() {
        XCTAssertEqual(NotationStemDirection.direction(forStaffPosition: 3), .down)
        XCTAssertEqual(NotationStemDirection.direction(forStaffPosition: 4), .up)
        XCTAssertEqual(NotationStemDirection.direction(forStaffPosition: 5), .up)
    }

    func testSixteenthDurationUsesQuarterBeatAndDisplayNames() {
        let duration = NotationDuration(denominator: 16)

        XCTAssertEqual(duration.denominator, 16)
        XCTAssertEqual(duration.durationInQuarterNotes, 0.25, accuracy: 0.0001)
        XCTAssertEqual(duration.displayName, "16th")
        XCTAssertEqual(duration.capitalizedDisplayName, "16th")
        XCTAssertEqual(duration.pluralDisplayName, "16th notes")
    }

    func testDottedDurationUsesOneAndAHalfTimesBaseValueAndHumanName() {
        let dottedQuarter = NotationDuration(denominator: 4, isDotted: true)
        let dottedSixteenth = NotationDuration(denominator: 16, isDotted: true)

        XCTAssertEqual(dottedQuarter.baseDurationInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(dottedQuarter.durationInQuarterNotes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(dottedQuarter.displayName, "quarter")
        XCTAssertEqual(dottedQuarter.capitalizedDisplayName, "Dotted quarter")
        XCTAssertEqual(dottedSixteenth.durationInQuarterNotes, 0.375, accuracy: 0.0001)
        XCTAssertNotEqual(dottedQuarter.id, NotationDuration(denominator: 4).id)
    }

    func testNotationDurationCodableDefaultsLegacyValuesToUndottedAndOmitsFalseFlag() throws {
        let legacy = try JSONDecoder().decode(
            NotationDuration.self,
            from: Data(#"{"denominator":4}"#.utf8)
        )
        let undottedData = try JSONEncoder().encode(NotationDuration(denominator: 4))
        let dottedData = try JSONEncoder().encode(NotationDuration(denominator: 4, isDotted: true))

        XCTAssertFalse(legacy.isDotted)
        XCTAssertFalse(String(decoding: undottedData, as: UTF8.self).contains("isDotted"))
        XCTAssertTrue(String(decoding: dottedData, as: UTF8.self).contains("isDotted"))
    }

    func testAugmentationDotLayoutMovesLineNotesIntoSpaceAbove() {
        let spacing = AppTheme.Timeline.notationStaffLineSpacing
        let staffTop: CGFloat = 20

        XCTAssertEqual(NotationAugmentationDotLayout.noteDotStaffPosition(for: 4), 3)
        XCTAssertEqual(NotationAugmentationDotLayout.noteDotStaffPosition(for: 3), 3)
        XCTAssertEqual(NotationAugmentationDotLayout.noteDotStaffPosition(for: -2), -3)

        let noteTarget = NotationAugmentationDotLayout.noteTarget(
            noteX: 100,
            noteStaffPosition: 4,
            staffTop: staffTop
        )
        let restTarget = NotationAugmentationDotLayout.restTarget(restX: 100, staffTop: staffTop)
        XCTAssertEqual(noteTarget.x, 100 + spacing, accuracy: 0.0001)
        XCTAssertEqual(noteTarget.y, restTarget.y, accuracy: 0.0001)
    }

    func testFiveDurationButtonsFitNotationTrackControls() {
        let buttonCount = CGFloat(NotationDuration.entryDenominators.count)
        let spacingCount = max(0, buttonCount - 1)
        let controlWidth = buttonCount * AppTheme.ControlSize.notationDurationButtonWidth
            + spacingCount * AppTheme.ControlSize.notationDurationButtonSpacing
        let availableWidth = AppTheme.Timeline.trackControlWidth - 2 * AppTheme.Spacing.md

        XCTAssertLessThanOrEqual(controlWidth, availableWidth)
        XCTAssertEqual(AppTheme.ControlSize.notationModeButtonWidth, 32)
    }

    func testThreeEntryModeButtonsFitNotationTrackControls() {
        let controlWidth = 3 * AppTheme.ControlSize.notationModeButtonWidth
            + 2 * AppTheme.Spacing.sm
        let availableWidth = AppTheme.Timeline.trackControlWidth - 2 * AppTheme.Spacing.md

        XCTAssertLessThanOrEqual(controlWidth, availableWidth)
    }

    func testNotationRestItemFactoryUsesGreedyAllowedDurationDecomposition() {
        let segments = NotationRestItemFactory.greedySegments(startOffset: 0, remaining: 3.5)

        XCTAssertEqual(segments.map(\.displayDuration.denominator), [2, 4, 8])
        XCTAssertEqual(segments.map(\.offsetInQuarterNotes), [0, 2, 3])
        XCTAssertEqual(segments.map(\.durationInQuarterNotes), [2, 1, 0.5])
        XCTAssertEqual(segments.map(\.isTail), [false, false, false])
    }

    func testNotationRestItemFactoryUsesTimelineToleranceForMinimumDuration() {
        let tolerance = NotationMeasureTiming.timelineTolerance

        let withinTolerance = NotationRestItemFactory.greedySegments(
            startOffset: 1,
            remaining: 0.125 - tolerance / 2
        )
        let outsideTolerance = NotationRestItemFactory.greedySegments(
            startOffset: 1,
            remaining: 0.125 - tolerance * 2
        )

        XCTAssertEqual(withinTolerance.map(\.displayDuration.denominator), [32])
        XCTAssertEqual(withinTolerance.map(\.offsetInQuarterNotes), [1])
        XCTAssertTrue(outsideTolerance.isEmpty)
    }

    func testNotationRestItemFactoryUsesSixteenthAsMinimumExactDuration() {
        let segments = NotationRestItemFactory.greedySegments(startOffset: 1.5, remaining: 0.25)

        XCTAssertEqual(segments.map(\.displayDuration.denominator), [16])
        XCTAssertEqual(segments.map(\.offsetInQuarterNotes), [1.5])
        XCTAssertEqual(segments.map(\.durationInQuarterNotes), [0.25])
    }

    func testNotationRestItemFactoryLetsCallerControlIDsAndSynthesizedState() throws {
        let synthesized = NotationRestItemFactory.restItems(
            measureNumber: 2,
            measureStartTime: 4,
            startOffset: 1,
            remaining: 1,
            isSynthesized: true
        ) { segment in
            "rest-\(segment.offsetInQuarterNotes)-\(segment.displayDuration.denominator)"
        }
        let persisted = NotationRestItemFactory.restItems(
            measureNumber: 2,
            measureStartTime: 4,
            startOffset: 1,
            remaining: 1
        )

        XCTAssertEqual(synthesized.map(\.id), ["rest-1.0-4"])
        XCTAssertEqual(synthesized.map(\.isSynthesized), [true])
        XCTAssertEqual(persisted.map(\.isSynthesized), [false])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(persisted.first?.id)))
    }

    func testNotationViewportFactoryDefaultWholeRestKeepsSynthesizedFieldsAndID() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 1.5,
            attributes: MeasureAttributes(
                keySignature: .cMajor,
                timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
                clef: .treble
            )
        )

        let item = try XCTUnwrap(NotationViewportFactory.notationItems(for: measure, from: []).first)

        XCTAssertEqual(item.id, "default-rest-main-1-0.0-1.5")
        XCTAssertEqual(item.kind, .rest)
        XCTAssertEqual(item.measureNumber, 1)
        XCTAssertEqual(item.measureStartTime, 0)
        XCTAssertEqual(item.offsetInQuarterNotes, 0)
        XCTAssertEqual(item.durationInQuarterNotes, 3)
        XCTAssertEqual(item.displayDuration.denominator, 1)
        XCTAssertTrue(item.isSynthesized)
    }

    func testNotationMeasureItemDecodesLegacyRestWithoutPitchOrSynthesizedFlag() throws {
        let json = """
        {
          "id": "legacy-rest",
          "kind": "rest",
          "measureNumber": 1,
          "measureStartTime": 0,
          "offsetInQuarterNotes": 0,
          "durationInQuarterNotes": 4,
          "displayDuration": { "denominator": 1 }
        }
        """

        let item = try JSONDecoder().decode(NotationMeasureItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.id, "legacy-rest")
        XCTAssertEqual(item.kind, .rest)
        XCTAssertNil(item.pitch)
        XCTAssertFalse(item.isSynthesized)
    }

    func testNotationMeasureItemPersistedCopyClearsSynthesizedStateAndNormalizesPitch() throws {
        let persistedNote = NotationMeasureItem(
            id: "note",
            kind: .note,
            pitch: NotationPitch(step: .g, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let synthesizedRest = NotationMeasureItem(
            id: "default-rest",
            kind: .rest,
            pitch: NotationPitch(step: .c, octave: 5),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2),
            isSynthesized: true
        )

        let noteCopy = persistedNote.persistedCopy()
        let restCopy = synthesizedRest.persistedCopy()

        XCTAssertEqual(noteCopy.id, "note")
        XCTAssertEqual(noteCopy.kind, .note)
        XCTAssertEqual(noteCopy.pitch, NotationPitch(step: .g, octave: 4))
        XCTAssertFalse(noteCopy.isSynthesized)
        XCTAssertNotEqual(restCopy.id, "default-rest")
        XCTAssertEqual(restCopy.kind, .rest)
        XCTAssertNil(restCopy.pitch)
        XCTAssertFalse(restCopy.isSynthesized)
    }

    func testNotationPitchMapperAppliesKeySignatureDefaultAlter() {
        let fSharp = NotationPitchMapper.pitch(
            forStaffPosition: 0,
            keySignature: KeySignature.normalized(from: "G major")
        )
        let bFlat = NotationPitchMapper.pitch(
            forStaffPosition: 4,
            keySignature: KeySignature.normalized(from: "F major")
        )

        XCTAssertEqual(fSharp.step, .f)
        XCTAssertEqual(fSharp.octave, 5)
        XCTAssertEqual(fSharp.alter, 1)
        XCTAssertEqual(bFlat.step, .b)
        XCTAssertEqual(bFlat.octave, 4)
        XCTAssertEqual(bFlat.alter, -1)
    }

    func testNotationPitchMapperSupportsLedgerRange() {
        let cMajor = KeySignature.normalized(from: "C major")

        XCTAssertEqual(
            NotationPitchMapper.pitch(
                forStaffPosition: NotationPitchMapper.minimumStaffPosition,
                keySignature: cMajor
            ),
            NotationPitch(step: .d, octave: 6)
        )
        XCTAssertEqual(
            NotationPitchMapper.pitch(
                forStaffPosition: NotationPitchMapper.maximumStaffPosition,
                keySignature: cMajor
            ),
            NotationPitch(step: .g, octave: 3)
        )
        XCTAssertEqual(
            NotationPitchMapper.pitch(forStaffPosition: -100, keySignature: cMajor),
            NotationPitch(step: .d, octave: 6)
        )
        XCTAssertEqual(
            NotationPitchMapper.pitch(forStaffPosition: 100, keySignature: cMajor),
            NotationPitch(step: .g, octave: 3)
        )
        XCTAssertEqual(
            NotationPitchMapper.staffPosition(for: NotationPitch(step: .d, octave: 6)),
            NotationPitchMapper.minimumStaffPosition
        )
        XCTAssertEqual(
            NotationPitchMapper.staffPosition(for: NotationPitch(step: .g, octave: 3)),
            NotationPitchMapper.maximumStaffPosition
        )
    }

    func testNotationPitchMapperUsesBassRangeAndKeepsStoredPitchesMappable() {
        let cMajor = KeySignature.normalized(from: "C major")

        XCTAssertEqual(NotationPitchMapper.editableStaffPositionRange(for: .treble), -5...13)
        XCTAssertEqual(NotationPitchMapper.editableStaffPositionRange(for: .bass), -3...15)
        XCTAssertEqual(
            NotationPitchMapper.pitch(forStaffPosition: -3, keySignature: cMajor, clef: .bass),
            NotationPitch(step: .d, octave: 4)
        )
        XCTAssertEqual(
            NotationPitchMapper.pitch(forStaffPosition: 15, keySignature: cMajor, clef: .bass),
            NotationPitch(step: .g, octave: 1)
        )
        XCTAssertEqual(
            NotationPitchMapper.staffPosition(for: NotationPitch(step: .d, octave: 4), clef: .bass),
            -3
        )
        XCTAssertEqual(
            NotationPitchMapper.staffPosition(for: NotationPitch(step: .g, octave: 1), clef: .bass),
            15
        )
        XCTAssertEqual(
            NotationPitchMapper.staffPosition(for: NotationPitch(step: .c, octave: 5), clef: .bass),
            -9
        )
        XCTAssertNil(NotationPitchMapper.adjacentPitch(
            from: NotationPitch(step: .d, octave: 4),
            staffPositionDelta: -1,
            keySignature: cMajor,
            clef: .bass
        ))
        XCTAssertNil(NotationPitchMapper.adjacentPitch(
            from: NotationPitch(step: .g, octave: 1),
            staffPositionDelta: 1,
            keySignature: cMajor,
            clef: .bass
        ))

        let staffTop: CGFloat = 50
        XCTAssertEqual(
            NotationNotePlacementResolver.staffPosition(
                forY: NotationNotePlacementResolver.yPosition(forStaffPosition: -3, staffTop: staffTop),
                staffTop: staffTop,
                clef: .bass
            ),
            -3
        )
        XCTAssertEqual(
            NotationNotePlacementResolver.staffPosition(
                forY: NotationNotePlacementResolver.yPosition(forStaffPosition: 15, staffTop: staffTop),
                staffTop: staffTop,
                clef: .bass
            ),
            15
        )
    }

    func testBassKeySignatureAccidentalsUseBassStaffPositions() {
        let sharps = KeySignature(fifths: 7, mode: .major, displayName: "C sharp major")
            .notationAccidentalGlyphs(for: .bass)
        let flats = KeySignature(fifths: -7, mode: .major, displayName: "C flat major")
            .notationAccidentalGlyphs(for: .bass)

        XCTAssertEqual(sharps.map(\.staffPositionFromTopLine), [2, 5, 1, 4, 7, 3, 6])
        XCTAssertEqual(flats.map(\.staffPositionFromTopLine), [6, 3, 7, 4, 8, 5, 9])
    }

    func testNotationPitchMapperAdjacentPitchRespectsBoundsAndKeySignature() throws {
        let cMajor = KeySignature.normalized(from: "C major")
        let fMajor = KeySignature.normalized(from: "F major")

        XCTAssertEqual(
            NotationPitchMapper.adjacentPitch(
                from: NotationPitch(step: .c, octave: 5),
                staffPositionDelta: 1,
                keySignature: cMajor
            ),
            NotationPitch(step: .b, octave: 4)
        )
        XCTAssertEqual(
            NotationPitchMapper.adjacentPitch(
                from: NotationPitch(step: .c, octave: 5),
                staffPositionDelta: -1,
                keySignature: cMajor
            ),
            NotationPitch(step: .d, octave: 5)
        )
        XCTAssertEqual(
            NotationPitchMapper.adjacentPitch(
                from: NotationPitch(step: .a, octave: 4),
                staffPositionDelta: -1,
                keySignature: fMajor
            ),
            NotationPitch(step: .b, octave: 4, alter: -1)
        )
        XCTAssertEqual(
            NotationPitchMapper.adjacentPitch(
                from: NotationPitch(step: .f, octave: 5),
                staffPositionDelta: -1,
                keySignature: cMajor
            ),
            NotationPitch(step: .g, octave: 5)
        )
        XCTAssertNil(NotationPitchMapper.adjacentPitch(
            from: NotationPitch(step: .d, octave: 6),
            staffPositionDelta: -1,
            keySignature: cMajor
        ))
        XCTAssertNil(NotationPitchMapper.adjacentPitch(
            from: NotationPitch(step: .g, octave: 3),
            staffPositionDelta: 1,
            keySignature: cMajor
        ))
    }

    func testNotationPitchMapsToMIDINoteNumbers() {
        XCTAssertEqual(NotationPitch(step: .c, octave: 4).midiNoteNumber, 60)
        XCTAssertEqual(NotationPitch(step: .f, octave: 5, alter: 1).midiNoteNumber, 78)
        XCTAssertEqual(NotationPitch(step: .b, octave: 4, alter: -1).midiNoteNumber, 70)
        XCTAssertEqual(NotationPitch(step: .c, octave: -2).midiNoteNumber, 0)
        XCTAssertEqual(NotationPitch(step: .b, octave: 10, alter: 1).midiNoteNumber, 127)
    }

    func testNotationNotePlacementResolverUsesSnappedClickInsideFullMeasureRest() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [
                NotationMeasureItem(
                    id: "explicit-whole-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 4,
                    displayDuration: NotationDuration(denominator: 1)
                )
            ]
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )

        let placement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: 160, y: 72),
            staffTop: 40,
            selectedDuration: NotationDuration(denominator: 4)
        ))

        XCTAssertEqual(placement.offsetInQuarterNotes, 3.25, accuracy: 0.0001)
        XCTAssertEqual(placement.pitch.step, .e)
        XCTAssertEqual(placement.pitch.octave, 4)
    }

    func testNotationNotePlacementResolverUsesSharedGridAcrossAdjacentRests() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [
                NotationMeasureItem(
                    id: "first-note",
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 5),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                ),
                NotationMeasureItem(
                    id: "first-eighth-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 0.5,
                    displayDuration: NotationDuration(denominator: 8)
                ),
                NotationMeasureItem(
                    id: "second-eighth-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1.5,
                    durationInQuarterNotes: 0.5,
                    displayDuration: NotationDuration(denominator: 8)
                ),
                NotationMeasureItem(
                    id: "half-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 2,
                    durationInQuarterNotes: 2,
                    displayDuration: NotationDuration(denominator: 2)
                )
            ]
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let xInsideSecondEighth = NotationMeasureLayout.notationAnchorX(
            geometry: geometry,
            offsetInQuarterNotes: 1.9,
            timeSignature: measure.attributes.timeSignature
        )

        let placement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: xInsideSecondEighth, y: 72),
            staffTop: 40,
            selectedDuration: NotationDuration(denominator: 4)
        ))

        XCTAssertEqual(placement.offsetInQuarterNotes, 2, accuracy: 0.0001)
        XCTAssertEqual(placement.durationInQuarterNotes, 1, accuracy: 0.0001)
    }

    func testNotationNotePlacementAllowsOverflowFromTrailingRestWithoutChangingRestPlacement() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [
                NotationMeasureItem(
                    id: "existing-note",
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 5),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 3,
                    displayDuration: NotationDuration(denominator: 2, isDotted: true)
                ),
                NotationMeasureItem(
                    id: "trailing-quarter-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 3,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let xInsideTrailingRest = NotationMeasureLayout.notationAnchorX(
            geometry: geometry,
            offsetInQuarterNotes: 3.5,
            timeSignature: measure.attributes.timeSignature
        )
        let duration = NotationDuration(denominator: 2)

        let placement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: xInsideTrailingRest, y: 72),
            staffTop: 40,
            selectedDuration: duration
        ))

        XCTAssertEqual(placement.offsetInQuarterNotes, 3.5, accuracy: 0.0001)
        XCTAssertNil(NotationNotePlacementResolver.restPlacement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: xInsideTrailingRest, y: 72),
            staffTop: 40,
            selectedDuration: duration
        ))
    }

    func testNotationRestPlacementResolverUsesSharedGridAcrossAdjacentRests() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [
                NotationMeasureItem(
                    id: "first-note",
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 5),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                ),
                NotationMeasureItem(
                    id: "first-eighth-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 0.5,
                    displayDuration: NotationDuration(denominator: 8)
                ),
                NotationMeasureItem(
                    id: "second-eighth-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1.5,
                    durationInQuarterNotes: 0.5,
                    displayDuration: NotationDuration(denominator: 8)
                ),
                NotationMeasureItem(
                    id: "half-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 2,
                    durationInQuarterNotes: 2,
                    displayDuration: NotationDuration(denominator: 2)
                )
            ]
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let xInsideSecondEighth = NotationMeasureLayout.notationAnchorX(
            geometry: geometry,
            offsetInQuarterNotes: 1.9,
            timeSignature: measure.attributes.timeSignature
        )

        let placement = try XCTUnwrap(NotationNotePlacementResolver.restPlacement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: xInsideSecondEighth, y: 72),
            staffTop: 40,
            selectedDuration: NotationDuration(denominator: 4)
        ))

        XCTAssertEqual(placement.offsetInQuarterNotes, 2, accuracy: 0.0001)
        XCTAssertEqual(placement.durationInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(placement.displayDuration.denominator, 4)
    }

    func testNotationNotePlacementResolverAllowsOverlapWithoutContiguousRestCapacity() throws {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [
                NotationMeasureItem(
                    id: "short-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 0.5,
                    displayDuration: NotationDuration(denominator: 8)
                ),
                NotationMeasureItem(
                    id: "next-note",
                    kind: .note,
                    pitch: NotationPitch(step: .e, octave: 4),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1.5,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let xInsideShortRest = NotationMeasureLayout.notationAnchorX(
            geometry: geometry,
            offsetInQuarterNotes: 1.25,
            timeSignature: measure.attributes.timeSignature
        )

        let placement = try XCTUnwrap(NotationNotePlacementResolver.placement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: xInsideShortRest, y: 72),
            staffTop: 40,
            selectedDuration: NotationDuration(denominator: 4)
        ))
        XCTAssertEqual(placement.offsetInQuarterNotes, 1.25, accuracy: 0.0001)
    }

    func testNotationRestPlacementResolverRejectsRestWithoutContiguousCapacity() {
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [
                NotationMeasureItem(
                    id: "short-rest",
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 0.5,
                    displayDuration: NotationDuration(denominator: 8)
                ),
                NotationMeasureItem(
                    id: "next-note",
                    kind: .note,
                    pitch: NotationPitch(step: .e, octave: 4),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1.5,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )
        let geometry = NotationMeasureCanvasGeometry(
            measureIndex: 0,
            cellStartX: 0,
            cellEndX: 200,
            contentStartX: 20,
            contentEndX: 180,
            staffStartX: 0,
            staffEndX: 200
        )
        let xInsideShortRest = NotationMeasureLayout.notationAnchorX(
            geometry: geometry,
            offsetInQuarterNotes: 1.25,
            timeSignature: measure.attributes.timeSignature
        )

        XCTAssertNil(NotationNotePlacementResolver.restPlacement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: xInsideShortRest, y: 72),
            staffTop: 40,
            selectedDuration: NotationDuration(denominator: 4)
        ))
    }

    func testNotationNotePlacementResolverClampsStaffPositionForPitchDrag() throws {
        let staffTop: CGFloat = 40
        let spacing = AppTheme.Timeline.notationStaffLineSpacing

        XCTAssertEqual(
            NotationNotePlacementResolver.clampedStaffPosition(
                forY: staffTop - spacing * 4,
                staffTop: staffTop
            ),
            NotationPitchMapper.minimumStaffPosition
        )
        XCTAssertEqual(
            NotationNotePlacementResolver.clampedStaffPosition(
                forY: staffTop + spacing * 8,
                staffTop: staffTop
            ),
            NotationPitchMapper.maximumStaffPosition
        )
        XCTAssertEqual(
            NotationNotePlacementResolver.clampedStaffPosition(
                forY: staffTop + spacing,
                staffTop: staffTop
            ),
            2
        )
    }

    func testNotationNotePlacementResolverAllowsExtendedEntryRange() {
        let staffTop: CGFloat = 40
        let spacing = AppTheme.Timeline.notationStaffLineSpacing

        XCTAssertEqual(
            NotationNotePlacementResolver.staffPosition(
                forY: NotationNotePlacementResolver.yPosition(
                    forStaffPosition: NotationPitchMapper.minimumStaffPosition,
                    staffTop: staffTop,
                    lineSpacing: spacing
                ),
                staffTop: staffTop,
                lineSpacing: spacing
            ),
            NotationPitchMapper.minimumStaffPosition
        )
        XCTAssertEqual(
            NotationNotePlacementResolver.staffPosition(
                forY: NotationNotePlacementResolver.yPosition(
                    forStaffPosition: NotationPitchMapper.maximumStaffPosition,
                    staffTop: staffTop,
                    lineSpacing: spacing
                ),
                staffTop: staffTop,
                lineSpacing: spacing
            ),
            NotationPitchMapper.maximumStaffPosition
        )
        XCTAssertNil(NotationNotePlacementResolver.staffPosition(
            forY: staffTop - spacing * 4,
            staffTop: staffTop,
            lineSpacing: spacing
        ))
        XCTAssertNil(NotationNotePlacementResolver.staffPosition(
            forY: staffTop + spacing * 8,
            staffTop: staffTop,
            lineSpacing: spacing
        ))
    }

    func testNotationNotePlacementResolverLedgerLinePositions() {
        XCTAssertEqual(
            NotationNotePlacementResolver.ledgerLineStaffPositions(forStaffPosition: -5),
            [-2, -4]
        )
        XCTAssertEqual(
            NotationNotePlacementResolver.ledgerLineStaffPositions(forStaffPosition: -1),
            []
        )
        XCTAssertEqual(
            NotationNotePlacementResolver.ledgerLineStaffPositions(forStaffPosition: 9),
            []
        )
        XCTAssertEqual(
            NotationNotePlacementResolver.ledgerLineStaffPositions(forStaffPosition: 13),
            [10, 12]
        )
    }

    func testLelandFontResourceIsBundledAndRegistered() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Leland", withExtension: "otf"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(NotationMusicFontRegistry.fontName, "Leland")
    }

    func testLelandRestGlyphPathsHaveBounds() throws {
        for symbol in [
            NotationSMuFLSymbol.restWhole,
            .restHalf,
            .restQuarter,
            .rest8th,
            .rest16th
        ] {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: 32.5
            ))

            XCTAssertFalse(glyphPath.path.isEmpty)
            XCTAssertGreaterThan(glyphPath.bounds.width, 0)
            XCTAssertGreaterThan(glyphPath.bounds.height, 0)
        }
    }

    func testNotationClefLayoutUsesExpectedFrameAndStaffTargets() {
        XCTAssertEqual(NotationClefLayout.frameSize, CGSize(width: 38, height: 60))
        XCTAssertEqual(NotationClefLayout.referenceAnchorY, 0)
        XCTAssertEqual(NotationClefLayout.targetY(for: .treble), 38)
        XCTAssertEqual(NotationClefLayout.targetY(for: .bass), 22)
        XCTAssertEqual(NotationClefLayout.targetY(for: .drums), 30)
    }

    func testNotationClefLayoutTransformAnchorsGlyphAtStaffTarget() throws {
        for symbol in [NotationClefSymbol.treble, .bass, .drums] {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: AppTheme.Timeline.notationClefFontSize
            ))
            let target = NotationClefLayout.target(for: symbol, in: NotationClefLayout.frameSize)
            let transformedAnchor = NotationClefLayout.referenceAnchor(for: glyphPath).applying(
                NotationClefLayout.transform(
                    for: glyphPath,
                    symbol: symbol,
                    in: NotationClefLayout.frameSize
                )
            )

            XCTAssertEqual(transformedAnchor.x, target.x, accuracy: 0.0001)
            XCTAssertEqual(transformedAnchor.y, target.y, accuracy: 0.0001)
        }
    }

    func testLelandClefGlyphPathsHaveBounds() throws {
        for symbol in [NotationClefSymbol.treble, .bass, .drums] {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: AppTheme.Timeline.notationClefFontSize
            ))
            var transform = NotationClefLayout.transform(
                for: glyphPath,
                symbol: symbol,
                in: NotationClefLayout.frameSize
            )
            let renderedBounds = try XCTUnwrap(glyphPath.path.copy(using: &transform)).boundingBox

            XCTAssertFalse(glyphPath.path.isEmpty)
            XCTAssertGreaterThan(glyphPath.bounds.width, 0)
            XCTAssertGreaterThan(glyphPath.bounds.height, 0)
            XCTAssertGreaterThanOrEqual(renderedBounds.minX, 0)
            XCTAssertLessThanOrEqual(renderedBounds.maxX, NotationClefLayout.frameSize.width)
            XCTAssertGreaterThanOrEqual(renderedBounds.minY, 0)
            XCTAssertLessThanOrEqual(renderedBounds.maxY, NotationClefLayout.frameSize.height)
        }
    }

    func testLelandDrumNoteheadGlyphPathsHaveBounds() throws {
        for symbol in [NotationDrumNoteheadSymbol.x, .circleX] {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: 32.5
            ))

            XCTAssertFalse(glyphPath.path.isEmpty)
            XCTAssertGreaterThan(glyphPath.bounds.width, 0)
            XCTAssertGreaterThan(glyphPath.bounds.height, 0)
        }
    }

    func testLelandDurationControlGlyphPathsHaveBounds() throws {
        for symbol in [
            NotationDurationControlSymbol.whole,
            .half,
            .quarter,
            .eighth,
            .sixteenth
        ] {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: AppTheme.ControlSize.notationDurationGlyphSize
            ))

            XCTAssertFalse(glyphPath.path.isEmpty)
            XCTAssertGreaterThan(glyphPath.bounds.width, 0)
            XCTAssertGreaterThan(glyphPath.bounds.height, 0)
        }
    }

    func testLelandAugmentationDotGlyphPathHasBounds() throws {
        let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
            for: NotationAugmentationDotSymbol.augmentationDot,
            fontSize: AppTheme.ControlSize.notationDurationGlyphSize
        ))

        XCTAssertFalse(glyphPath.path.isEmpty)
        XCTAssertGreaterThan(glyphPath.bounds.width, 0)
        XCTAssertGreaterThan(glyphPath.bounds.height, 0)
    }

    func testLelandStaffNoteGlyphPathsHaveBounds() throws {
        for symbol in allStaffNoteSymbols {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: 32.5
            ))

            XCTAssertFalse(glyphPath.path.isEmpty)
            XCTAssertGreaterThan(glyphPath.bounds.width, 0)
            XCTAssertGreaterThan(glyphPath.bounds.height, 0)
        }
    }

    func testLelandStaffNoteGlyphTransformAnchorsNoteheadAtTargetPoint() throws {
        let target = CGPoint(x: 42, y: 73)

        for symbol in allStaffNoteSymbols {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: 32.5
            ))
            let anchor = try XCTUnwrap(NotationMusicFontRegistry.noteheadAnchor(
                for: symbol,
                fontSize: 32.5
            ))
            let transformedAnchor = anchor.applying(glyphPath.anchoredTransform(
                anchor: anchor,
                target: target
            ))

            XCTAssertEqual(transformedAnchor.x, target.x, accuracy: 0.0001)
            XCTAssertEqual(transformedAnchor.y, target.y, accuracy: 0.0001)
        }
    }

    func testDirectionSpecificStaffGlyphsExtendFromOppositeSidesOfNotehead() throws {
        let target = CGPoint(x: 42, y: 73)

        for expectation in directionalStaffSymbolExpectations {
            let upSymbol = expectation.up
            let downSymbol = expectation.down
            let upPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(for: upSymbol, fontSize: 32.5))
            let downPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(for: downSymbol, fontSize: 32.5))
            let upAnchor = try XCTUnwrap(NotationMusicFontRegistry.noteheadAnchor(for: upSymbol, fontSize: 32.5))
            let downAnchor = try XCTUnwrap(NotationMusicFontRegistry.noteheadAnchor(for: downSymbol, fontSize: 32.5))
            let upBounds = upPath.bounds.applying(upPath.anchoredTransform(anchor: upAnchor, target: target))
            let downBounds = downPath.bounds.applying(downPath.anchoredTransform(anchor: downAnchor, target: target))

            XCTAssertLessThan(upBounds.minY, target.y - 10)
            XCTAssertGreaterThan(downBounds.maxY, target.y + 10)
            XCTAssertGreaterThan(target.y - upBounds.minY, upBounds.maxY - target.y)
            XCTAssertGreaterThan(downBounds.maxY - target.y, target.y - downBounds.minY)
        }
    }

    func testLelandDurationControlGlyphPathsCenterInsideButtonFrame() throws {
        let buttonSize = CGSize(
            width: AppTheme.ControlSize.notationDurationButtonWidth,
            height: AppTheme.ControlSize.notationDurationControlHeight
        )

        for symbol in [
            NotationDurationControlSymbol.whole,
            .half,
            .quarter,
            .eighth,
            .sixteenth
        ] {
            let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
                for: symbol,
                fontSize: AppTheme.ControlSize.notationDurationGlyphSize
            ))
            let centeredBounds = glyphPath.bounds.applying(glyphPath.centeredTransform(in: buttonSize))

            XCTAssertEqual(centeredBounds.midX, buttonSize.width / 2, accuracy: 0.0001)
            XCTAssertEqual(centeredBounds.midY, buttonSize.height / 2, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(centeredBounds.width, buttonSize.width)
            XCTAssertLessThanOrEqual(centeredBounds.height, buttonSize.height)
        }
    }

    func testNotationDurationControlHelpTextIncludesNameAndShortcuts() {
        let expectations: [(denominator: Int, tooltip: String)] = [
            (
                1,
                "Whole (semibreve) note (7; Num7)\nSet duration: whole (semibreve) note"
            ),
            (
                2,
                "Half (minim) note (6; Num6)\nSet duration: half (minim) note"
            ),
            (
                4,
                "Quarter (crotchet) note (5; Num5)\nSet duration: quarter (crotchet) note"
            ),
            (
                8,
                "Eighth (quaver) note (4; Num4)\nSet duration: eighth (quaver) note"
            ),
            (
                16,
                "16th (semiquaver) note (3; Num3)\nSet duration: 16th (semiquaver) note"
            )
        ]

        for expectation in expectations {
            XCTAssertEqual(
                NotationDurationControlHelpText.tooltip(for: NotationDuration(denominator: expectation.denominator)),
                expectation.tooltip
            )
        }

        let quarter = NotationDuration(denominator: 4)
        XCTAssertEqual(
            NotationDurationControlHelpText.accessibilityLabel(for: quarter),
            "Quarter note duration"
        )
        XCTAssertEqual(
            NotationDurationControlHelpText.accessibilityHint(for: quarter),
            "Sets notation duration to quarter note"
        )
    }

    func testAugmentationDotHelpTextMatchesShortcutDescription() {
        XCTAssertEqual(
            NotationAugmentationDotHelpText.tooltip,
            "Augmentation dot (.; Num.; Num,)\nToggle duration dot"
        )
        XCTAssertEqual(NotationAugmentationDotHelpText.accessibilityLabel, "Augmentation dot")
    }

    func testWholeRestVisualCenterUsesStandardStaffPosition() {
        let y = NotationMeasureLayout.wholeRestVisualCenterY(
            staffTop: 10,
            lineSpacing: 8
        )

        XCTAssertEqual(y, 22, accuracy: 0.0001)
    }
}
