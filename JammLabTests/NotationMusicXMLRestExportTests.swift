import Foundation
import XCTest
@testable import JammLab

final class NotationMusicXMLRestExportTests: XCTestCase {
    func testMusicXMLExportIncludesSplitNotationRests() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: splitQuarterQuarterHalfNotationItems(),
            harmonySymbols: [
                HarmonySymbol(time: 1.5, measureNumber: 1, offsetInQuarterNotes: 3, rawText: "Fmaj7")
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let firstMeasure = try XCTUnwrap(part.elements(forName: "measure").first)
        let notes = firstMeasure.elements(forName: "note")
        let harmonies = firstMeasure.elements(forName: "harmony")
        let halfRest = try XCTUnwrap(notes.last)
        let harmony = try XCTUnwrap(harmonies.first)

        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes.map { $0.elements(forName: "duration").first?.stringValue }, ["480", "480", "960"])
        XCTAssertEqual(notes.map { $0.elements(forName: "type").first?.stringValue }, ["quarter", "quarter", "half"])
        XCTAssertEqual(try firstXMLChild(named: "offset", in: harmony).stringValue, "480")
        try assertXMLChild(harmony, precedes: halfRest, in: firstMeasure)
        XCTAssertTrue(notes.allSatisfy { note in
            note.elements(forName: "rest").first?.attribute(forName: "measure") == nil
        })
        XCTAssertTrue(notes.allSatisfy { $0.elements(forName: "dot").isEmpty })
    }

    func testMusicXMLHarmonyAtNotationItemBoundaryUsesNextItemCursor() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: splitQuarterQuarterHalfNotationItems(),
            harmonySymbols: [
                HarmonySymbol(time: 1, measureNumber: 1, offsetInQuarterNotes: 2, rawText: "Dm7")
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let firstMeasure = try XCTUnwrap(part.elements(forName: "measure").first)
        let notes = firstMeasure.elements(forName: "note")
        let harmony = try XCTUnwrap(firstMeasure.elements(forName: "harmony").first)
        let thirdRest = try XCTUnwrap(notes.last)

        XCTAssertEqual(try firstXMLChild(named: "offset", in: harmony).stringValue, "0")
        try assertXMLChild(harmony, precedes: thirdRest, in: firstMeasure)
    }

    func testMusicXMLExportIncludesPitchedNotationNoteWithoutBeam() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "G major",
            notationItems: [
                NotationMeasureItem(
                    kind: .note,
                    pitch: NotationPitch(step: .f, octave: 5, alter: 1),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 0.5,
                    displayDuration: NotationDuration(denominator: 8)
                ),
                NotationMeasureItem(
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0.5,
                    durationInQuarterNotes: 3.5,
                    displayDuration: NotationDuration(denominator: 2)
                )
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let firstMeasure = try XCTUnwrap(part.elements(forName: "measure").first)
        let note = try XCTUnwrap(firstMeasure.elements(forName: "note").first)
        let pitch = try firstXMLChild(named: "pitch", in: note)

        XCTAssertEqual(try firstXMLChild(named: "step", in: pitch).stringValue, "F")
        XCTAssertEqual(try firstXMLChild(named: "alter", in: pitch).stringValue, "1")
        XCTAssertEqual(try firstXMLChild(named: "octave", in: pitch).stringValue, "5")
        XCTAssertEqual(try firstXMLChild(named: "duration", in: note).stringValue, "240")
        XCTAssertEqual(try firstXMLChild(named: "type", in: note).stringValue, "eighth")
        XCTAssertTrue(note.elements(forName: "dot").isEmpty)
        XCTAssertTrue(note.elements(forName: "beam").isEmpty)
    }

    func testMusicXMLExportIncludesSixteenthNoteAndRestWithoutBeams() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                NotationMeasureItem(
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 5),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 0.25,
                    displayDuration: NotationDuration(denominator: 16)
                ),
                NotationMeasureItem(
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0.25,
                    durationInQuarterNotes: 0.25,
                    displayDuration: NotationDuration(denominator: 16)
                ),
                NotationMeasureItem(
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0.5,
                    durationInQuarterNotes: 3.5,
                    displayDuration: NotationDuration(denominator: 2)
                )
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let firstMeasure = try XCTUnwrap(part.elements(forName: "measure").first)
        let notes = firstMeasure.elements(forName: "note")
        let sixteenthNote = try XCTUnwrap(notes.first)
        let sixteenthRest = try XCTUnwrap(notes.dropFirst().first)

        XCTAssertNotNil(sixteenthNote.elements(forName: "pitch").first)
        XCTAssertNotNil(sixteenthRest.elements(forName: "rest").first)
        for item in [sixteenthNote, sixteenthRest] {
            XCTAssertEqual(try firstXMLChild(named: "duration", in: item).stringValue, "120")
            XCTAssertEqual(try firstXMLChild(named: "type", in: item).stringValue, "16th")
            XCTAssertTrue(item.elements(forName: "beam").isEmpty)
        }
    }

    func testMusicXMLExportIncludesAugmentationDotForDottedNoteAndRest() throws {
        let dottedQuarter = NotationDuration(denominator: 4, isDotted: true)
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                NotationMeasureItem(
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 5),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: dottedQuarter.durationInQuarterNotes,
                    displayDuration: dottedQuarter
                ),
                NotationMeasureItem(
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1.5,
                    durationInQuarterNotes: dottedQuarter.durationInQuarterNotes,
                    displayDuration: dottedQuarter
                ),
                NotationMeasureItem(
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 3,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let firstMeasure = try XCTUnwrap(part.elements(forName: "measure").first)
        let exportedItems = firstMeasure.elements(forName: "note")
        let dottedItems = Array(exportedItems.prefix(2))

        XCTAssertEqual(dottedItems.count, 2)
        for item in dottedItems {
            XCTAssertEqual(try firstXMLChild(named: "duration", in: item).stringValue, "720")
            XCTAssertEqual(try firstXMLChild(named: "type", in: item).stringValue, "quarter")
            XCTAssertEqual(item.elements(forName: "dot").count, 1)
            let children = childElements(in: item)
            let typeIndex = try XCTUnwrap(children.firstIndex { $0.name == "type" })
            let dotIndex = try XCTUnwrap(children.firstIndex { $0.name == "dot" })
            XCTAssertEqual(dotIndex, typeIndex + 1)
        }
        XCTAssertNotNil(dottedItems.first?.elements(forName: "pitch").first)
        XCTAssertNotNil(dottedItems.last?.elements(forName: "rest").first)
        XCTAssertEqual(childElements(in: dottedItems[0]).compactMap(\.name), [
            "pitch", "duration", "voice", "type", "dot"
        ])
        XCTAssertEqual(childElements(in: dottedItems[1]).compactMap(\.name), [
            "rest", "duration", "voice", "type", "dot"
        ])

        let undottedRest = try XCTUnwrap(exportedItems.last)
        XCTAssertEqual(childElements(in: undottedRest).compactMap(\.name), [
            "rest", "duration", "voice", "type"
        ])
        XCTAssertTrue(undottedRest.elements(forName: "dot").isEmpty)
    }

    func testMusicXMLExportsExplicitSharpNaturalAndFlatInSchemaOrder() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 8),
            duration: 8,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                NotationMeasureItem(
                    id: "sharp",
                    kind: .note,
                    pitch: NotationPitch(step: .f, octave: 4),
                    explicitAccidental: .sharp,
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                ),
                NotationMeasureItem(
                    id: "natural",
                    kind: .note,
                    pitch: NotationPitch(step: .f, octave: 4, alter: 1),
                    explicitAccidental: .natural,
                    measureNumber: 2,
                    measureStartTime: 2,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                ),
                NotationMeasureItem(
                    id: "flat",
                    kind: .note,
                    pitch: NotationPitch(step: .b, octave: 4),
                    explicitAccidental: .flat,
                    measureNumber: 3,
                    measureStartTime: 4,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let part = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
        let measures = part.elements(forName: "measure")
        let sharpNote = try XCTUnwrap(measures[0].elements(forName: "note").first {
            $0.elements(forName: "pitch").first?.elements(forName: "step").first?.stringValue == "F"
        })
        let naturalNote = try XCTUnwrap(measures[1].elements(forName: "note").first {
            $0.elements(forName: "pitch").first?.elements(forName: "step").first?.stringValue == "F"
        })
        let flatNote = try XCTUnwrap(measures[2].elements(forName: "note").first {
            $0.elements(forName: "pitch").first?.elements(forName: "step").first?.stringValue == "B"
        })

        XCTAssertEqual(
            sharpNote.elements(forName: "pitch").first?
                .elements(forName: "alter").first?.stringValue,
            "1"
        )
        XCTAssertEqual(sharpNote.elements(forName: "accidental").first?.stringValue, "sharp")
        XCTAssertTrue(
            naturalNote.elements(forName: "pitch").first?
                .elements(forName: "alter").isEmpty == true
        )
        XCTAssertEqual(naturalNote.elements(forName: "accidental").first?.stringValue, "natural")
        XCTAssertEqual(
            flatNote.elements(forName: "pitch").first?
                .elements(forName: "alter").first?.stringValue,
            "-1"
        )
        XCTAssertEqual(flatNote.elements(forName: "accidental").first?.stringValue, "flat")
        for note in [sharpNote, naturalNote, flatNote] {
            let names = childElements(in: note).compactMap(\.name)
            let typeIndex = try XCTUnwrap(names.firstIndex(of: "type"))
            let accidentalIndex = try XCTUnwrap(names.firstIndex(of: "accidental"))
            XCTAssertEqual(accidentalIndex, typeIndex + 1)
        }
    }

    func testMusicXMLExportsChordOverlapsVoicesAndOneGlobalRestSequence() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 2),
            duration: 2,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                pitchedItem(id: "c", step: .c, offset: 0, duration: 2),
                pitchedItem(id: "e", step: .e, offset: 0, duration: 2),
                pitchedItem(id: "g", step: .g, offset: 1, duration: 2)
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let measure = try XCTUnwrap(document.rootElement()?
            .elements(forName: "part").first?
            .elements(forName: "measure").first)
        let notes = measure.elements(forName: "note")
        let pitched = notes.filter { !$0.elements(forName: "pitch").isEmpty }
        let rests = notes.filter { !$0.elements(forName: "rest").isEmpty }

        XCTAssertEqual(pitched.count, 3)
        XCTAssertEqual(pitched.filter { !$0.elements(forName: "chord").isEmpty }.count, 1)
        XCTAssertEqual(Set(pitched.compactMap { $0.elements(forName: "voice").first?.stringValue }), ["1", "2"])
        XCTAssertEqual(rests.count, 1)
        XCTAssertEqual(rests.first?.elements(forName: "voice").first?.stringValue, "1")
        XCTAssertEqual(measure.elements(forName: "backup").count, 1)
        XCTAssertFalse(measure.elements(forName: "forward").isEmpty)
    }

    func testMusicXMLKeepsTiedContinuationsInTheirOriginalVoicesAcrossMeasures() throws {
        let lowTargetID = "low-target"
        let highTargetID = "high-target"
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                NotationMeasureItem(
                    id: "low-source",
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 4),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 4,
                    displayDuration: NotationDuration(denominator: 1),
                    tieTargetItemID: lowTargetID
                ),
                NotationMeasureItem(
                    id: "high-source",
                    kind: .note,
                    pitch: NotationPitch(step: .g, octave: 4),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 3,
                    displayDuration: NotationDuration(denominator: 2, isDotted: true),
                    tieTargetItemID: highTargetID
                ),
                NotationMeasureItem(
                    id: lowTargetID,
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 4),
                    measureNumber: 2,
                    measureStartTime: 2,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                ),
                NotationMeasureItem(
                    id: highTargetID,
                    kind: .note,
                    pitch: NotationPitch(step: .g, octave: 4),
                    measureNumber: 2,
                    measureStartTime: 2,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let measures = try XCTUnwrap(document.rootElement()?.elements(forName: "part").first)
            .elements(forName: "measure")
        XCTAssertEqual(measures.count, 2)

        let firstPitched = measures[0].elements(forName: "note").filter { !$0.elements(forName: "pitch").isEmpty }
        let secondPitched = measures[1].elements(forName: "note").filter { !$0.elements(forName: "pitch").isEmpty }
        XCTAssertEqual(firstPitched.compactMap { $0.elements(forName: "voice").first?.stringValue }, ["1", "2"])
        XCTAssertEqual(secondPitched.compactMap { $0.elements(forName: "voice").first?.stringValue }, ["1", "2"])
        XCTAssertTrue(secondPitched.allSatisfy { $0.elements(forName: "chord").isEmpty })
        XCTAssertEqual(measures[0].elements(forName: "backup").first?.elements(forName: "duration").first?.stringValue, "1920")
        XCTAssertEqual(measures[1].elements(forName: "backup").first?.elements(forName: "duration").first?.stringValue, "1920")
        let secondMeasureRests = measures[1].elements(forName: "note").filter {
            !$0.elements(forName: "rest").isEmpty
        }
        XCTAssertFalse(secondMeasureRests.isEmpty)
        XCTAssertTrue(secondMeasureRests.allSatisfy {
            $0.elements(forName: "voice").first?.stringValue == "1"
        })
        XCTAssertEqual(
            secondMeasureRests.compactMap {
                Int($0.elements(forName: "duration").first?.stringValue ?? "")
            }.reduce(0, +),
            1440
        )
    }

    func testMusicXMLRendersGlobalRestsInTheOnlyLocalVoiceWhenItIsVoiceTwo() throws {
        let targetID = "voice-two-target"
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            notationItems: [
                NotationMeasureItem(
                    id: "voice-one-blocker",
                    kind: .note,
                    pitch: NotationPitch(step: .c, octave: 4),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 4,
                    displayDuration: NotationDuration(denominator: 1)
                ),
                NotationMeasureItem(
                    id: "voice-two-source",
                    kind: .note,
                    pitch: NotationPitch(step: .g, octave: 4),
                    measureNumber: 1,
                    measureStartTime: 0,
                    offsetInQuarterNotes: 1,
                    durationInQuarterNotes: 3,
                    displayDuration: NotationDuration(denominator: 2, isDotted: true),
                    tieTargetItemID: targetID
                ),
                NotationMeasureItem(
                    id: targetID,
                    kind: .note,
                    pitch: NotationPitch(step: .g, octave: 4),
                    measureNumber: 2,
                    measureStartTime: 2,
                    offsetInQuarterNotes: 0,
                    durationInQuarterNotes: 1,
                    displayDuration: NotationDuration(denominator: 4)
                )
            ]
        )

        let document = try exportedMusicXMLDocument(for: state)
        let secondMeasure = try XCTUnwrap(document.rootElement()?
            .elements(forName: "part").first?
            .elements(forName: "measure").last)
        let notes = secondMeasure.elements(forName: "note")

        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.allSatisfy {
            $0.elements(forName: "voice").first?.stringValue == "2"
        })
        XCTAssertFalse(notes.filter { !$0.elements(forName: "rest").isEmpty }.isEmpty)
        XCTAssertTrue(secondMeasure.elements(forName: "backup").isEmpty)
    }

    private func exportedMusicXMLDocument(for state: NotationScoreState) throws -> XMLDocument {
        let data = try NotationExportService().export(
            NotationExportRequest(displayName: "Song", score: state),
            format: .musicXML
        )
        return try XMLDocument(data: data)
    }

    private func childElements(in element: XMLElement) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }
    }

    private func assertXMLChild(
        _ firstElement: XMLElement,
        precedes secondElement: XMLElement,
        in parentElement: XMLElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let elements = childElements(in: parentElement)
        let firstIndex = try XCTUnwrap(elements.firstIndex { $0 === firstElement }, file: file, line: line)
        let secondIndex = try XCTUnwrap(elements.firstIndex { $0 === secondElement }, file: file, line: line)
        XCTAssertLessThan(firstIndex, secondIndex, file: file, line: line)
    }

    private func firstXMLChild(
        named name: String,
        in element: XMLElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XMLElement {
        try XCTUnwrap(element.elements(forName: name).first, file: file, line: line)
    }

    private func splitQuarterQuarterHalfNotationItems() -> [NotationMeasureItem] {
        [
            NotationMeasureItem(
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 2,
                durationInQuarterNotes: 2,
                displayDuration: NotationDuration(denominator: 2)
            )
        ]
    }

    private func pitchedItem(
        id: String,
        step: NotationPitchStep,
        offset: Double,
        duration: Double
    ) -> NotationMeasureItem {
        NotationMeasureItem(
            id: id,
            kind: .note,
            pitch: NotationPitch(step: step, octave: 4),
            measureNumber: 1,
            measureStartTime: 0,
            offsetInQuarterNotes: offset,
            durationInQuarterNotes: duration,
            displayDuration: NotationDuration(denominator: 2)
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
}
