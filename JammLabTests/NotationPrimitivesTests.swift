import XCTest
@testable import JammLab

final class NotationPrimitivesTests: XCTestCase {
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
