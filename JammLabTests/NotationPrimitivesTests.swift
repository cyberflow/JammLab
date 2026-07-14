import CoreGraphics
import XCTest
@testable import JammLab

final class NotationPrimitivesTests: XCTestCase {
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

        XCTAssertEqual(whole, .restWhole)
        XCTAssertEqual(whole.codepoint, 0xE4E3)
        XCTAssertEqual(half, .restHalf)
        XCTAssertEqual(half.codepoint, 0xE4E4)
        XCTAssertEqual(quarter, .restQuarter)
        XCTAssertEqual(quarter.codepoint, 0xE4E5)
        XCTAssertEqual(eighth, .rest8th)
        XCTAssertEqual(eighth.codepoint, 0xE4E6)
        XCTAssertEqual(quarter.glyph.unicodeScalars.first?.value, 0xE4E5)
    }

    func testNotationSMuFLDurationControlSymbolsMapDurationsToLelandMetNoteCodepoints() throws {
        let whole = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 1)))
        let half = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 2)))
        let quarter = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 4)))
        let eighth = try XCTUnwrap(NotationDurationControlSymbol(duration: NotationDuration(denominator: 8)))

        XCTAssertEqual(whole, .whole)
        XCTAssertEqual(whole.codepoint, 0xECA2)
        XCTAssertEqual(half, .half)
        XCTAssertEqual(half.codepoint, 0xECA3)
        XCTAssertEqual(quarter, .quarter)
        XCTAssertEqual(quarter.codepoint, 0xECA5)
        XCTAssertEqual(eighth, .eighth)
        XCTAssertEqual(eighth.codepoint, 0xECA7)
        XCTAssertEqual(eighth.glyph.unicodeScalars.first?.value, 0xECA7)
    }

    func testNotationStaffNoteSymbolsReuseLelandMetNoteCodepoints() throws {
        let whole = try XCTUnwrap(NotationStaffNoteSymbol(duration: NotationDuration(denominator: 1)))
        let half = try XCTUnwrap(NotationStaffNoteSymbol(duration: NotationDuration(denominator: 2)))
        let quarter = try XCTUnwrap(NotationStaffNoteSymbol(duration: NotationDuration(denominator: 4)))
        let eighth = try XCTUnwrap(NotationStaffNoteSymbol(duration: NotationDuration(denominator: 8)))

        XCTAssertEqual(whole.codepoint, 0xECA2)
        XCTAssertEqual(half.codepoint, 0xECA3)
        XCTAssertEqual(quarter.codepoint, 0xECA5)
        XCTAssertEqual(eighth.codepoint, 0xECA7)
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
            remaining: 0.5 - tolerance / 2
        )
        let outsideTolerance = NotationRestItemFactory.greedySegments(
            startOffset: 1,
            remaining: 0.5 - tolerance * 2
        )

        XCTAssertEqual(withinTolerance.map(\.displayDuration.denominator), [8])
        XCTAssertEqual(withinTolerance.map(\.offsetInQuarterNotes), [1])
        XCTAssertTrue(outsideTolerance.isEmpty)
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

        XCTAssertEqual(item.id, "default-rest-1-0.0-1.5")
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

    func testNotationNotePlacementResolverForcesFullMeasureWholeRestToBeatOne() throws {
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

        XCTAssertEqual(placement.offsetInQuarterNotes, 0, accuracy: 0.0001)
        XCTAssertEqual(placement.targetRestID, "explicit-whole-rest")
        XCTAssertEqual(placement.pitch.step, .e)
        XCTAssertEqual(placement.pitch.octave, 4)
    }

    func testNotationNotePlacementResolverTargetsContainingShortRestWithFollowingCapacity() throws {
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

        XCTAssertEqual(placement.targetRestID, "second-eighth-rest")
        XCTAssertEqual(placement.offsetInQuarterNotes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(placement.durationInQuarterNotes, 1, accuracy: 0.0001)
    }

    func testNotationRestPlacementResolverTargetsContainingShortRestWithFollowingCapacity() throws {
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

        XCTAssertEqual(placement.targetRestID, "second-eighth-rest")
        XCTAssertEqual(placement.offsetInQuarterNotes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(placement.durationInQuarterNotes, 1, accuracy: 0.0001)
        XCTAssertEqual(placement.displayDuration.denominator, 4)
    }

    func testNotationNotePlacementResolverRejectsRestWithoutContiguousCapacity() {
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

        XCTAssertNil(NotationNotePlacementResolver.placement(
            in: measure,
            geometry: geometry,
            point: CGPoint(x: xInsideShortRest, y: 72),
            staffTop: 40,
            selectedDuration: NotationDuration(denominator: 4)
        ))
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

    func testNotationEntryRecomposerPreservesPersistedItemsAndCopiesSynthesizedItems() throws {
        let note = NotationMeasureItem(
            id: "existing-note",
            kind: .note,
            pitch: NotationPitch(step: .c, octave: 5),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 0,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let targetRest = NotationMeasureItem(
            id: "target-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4),
            isSynthesized: true
        )
        let trailingRest = NotationMeasureItem(
            id: "trailing-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2),
            isSynthesized: true
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [note, targetRest, trailingRest]
        )
        let span = try XCTUnwrap(NotationNotePlacementResolver.restSpan(
            in: measure,
            from: targetRest,
            requiredDurationInQuarterNotes: 1
        ))
        let inserted = NotationMeasureItem(
            id: "inserted-note",
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )

        let recomposed = NotationEntryRecomposer.recomposedItems(
            in: measure,
            replacing: span,
            with: inserted
        )

        XCTAssertEqual(recomposed[0].id, "existing-note")
        XCTAssertEqual(recomposed[1].id, "inserted-note")
        XCTAssertNotEqual(recomposed[2].id, "trailing-rest")
        XCTAssertEqual(recomposed.map(\.kind), [.note, .note, .rest])
        XCTAssertEqual(recomposed[0].pitch, NotationPitch(step: .c, octave: 5))
        XCTAssertFalse(recomposed[0].isSynthesized)
        XCTAssertFalse(recomposed[2].isSynthesized)
    }

    func testNotationEntryRecomposerSplitsTailToNextQuarterBoundary() throws {
        let targetRest = NotationMeasureItem(
            id: "second-eighth-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1.5,
            durationInQuarterNotes: 0.5,
            displayDuration: NotationDuration(denominator: 8)
        )
        let followingRest = NotationMeasureItem(
            id: "half-rest",
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 2,
            durationInQuarterNotes: 2,
            displayDuration: NotationDuration(denominator: 2)
        )
        let measure = ScoreMeasure(
            number: 1,
            startTime: 0,
            endTime: 2,
            attributes: .defaultTreble,
            notationItems: [targetRest, followingRest]
        )
        let span = try XCTUnwrap(NotationNotePlacementResolver.restSpan(
            in: measure,
            from: targetRest,
            requiredDurationInQuarterNotes: 1
        ))
        let inserted = NotationMeasureItem(
            id: "inserted-note",
            kind: .note,
            pitch: NotationPitch(step: .e, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: 1.5,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )

        let recomposed = NotationEntryRecomposer.recomposedItems(
            in: measure,
            replacing: span,
            with: inserted
        )

        XCTAssertEqual(recomposed.map(\.kind), [.note, .rest, .rest])
        XCTAssertEqual(recomposed.map(\.offsetInQuarterNotes), [1.5, 2.5, 3])
        XCTAssertEqual(recomposed.map(\.durationInQuarterNotes), [1, 0.5, 1])
        XCTAssertEqual(recomposed.map(\.displayDuration.denominator), [4, 8, 4])
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

    func testLelandWholeRestGlyphPathHasBounds() throws {
        let glyphPath = try XCTUnwrap(NotationMusicFontRegistry.glyphPath(
            for: .restWhole,
            fontSize: 32.5
        ))

        XCTAssertFalse(glyphPath.path.isEmpty)
        XCTAssertGreaterThan(glyphPath.bounds.width, 0)
        XCTAssertGreaterThan(glyphPath.bounds.height, 0)
    }

    func testLelandDurationControlGlyphPathsHaveBounds() throws {
        for symbol in [
            NotationDurationControlSymbol.whole,
            .half,
            .quarter,
            .eighth
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

    func testLelandStaffNoteGlyphPathsHaveBounds() throws {
        for symbol in [
            NotationStaffNoteSymbol.whole,
            .half,
            .quarter,
            .eighth
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

    func testLelandStaffNoteGlyphTransformAnchorsNoteheadAtTargetPoint() throws {
        let target = CGPoint(x: 42, y: 73)

        for symbol in [
            NotationStaffNoteSymbol.whole,
            .half,
            .quarter,
            .eighth
        ] {
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

    func testLelandDurationControlGlyphPathsCenterInsideButtonFrame() throws {
        let buttonSize = CGSize(
            width: AppTheme.ControlSize.notationDurationButtonWidth,
            height: AppTheme.ControlSize.notationDurationControlHeight
        )

        for symbol in [
            NotationDurationControlSymbol.whole,
            .half,
            .quarter,
            .eighth
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

    func testWholeRestVisualCenterUsesStandardStaffPosition() {
        let y = NotationMeasureLayout.wholeRestVisualCenterY(
            staffTop: 10,
            lineSpacing: 8
        )

        XCTAssertEqual(y, 22, accuracy: 0.0001)
    }
}
