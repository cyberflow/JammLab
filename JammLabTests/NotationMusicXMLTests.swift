import Foundation
import XCTest
@testable import JammLab

final class NotationMusicXMLTests: XCTestCase {
    func testMusicXMLExportIncludesMeasuresAttributesHarmonyAndRegionDirections() throws {
        let regionID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(
                duration: 8,
                markers: [timeSignatureMarker(time: 4, beatsPerBar: 3)]
            ),
            duration: 8,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "G major",
            harmonySymbols: [
                HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "Cmaj7"),
                HarmonySymbol(time: 1.5, measureNumber: 1, offsetInQuarterNotes: 3, rawText: "Bb13(#11)/D")
            ],
            notes: [
                TimecodedNote(id: regionID, kind: .region, time: 2, duration: 2, title: "Verse")
            ]
        )
        let data = try NotationExportService(renderers: [
            MusicXMLNotationExportRenderer(appVersionProvider: { "9.8.7" })
        ]).export(
            NotationExportRequest(displayName: "Song", score: state, tempoBPM: 120),
            format: .musicXML
        )
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        let document = try XMLDocument(data: data)
        let root = try XCTUnwrap(document.rootElement())
        let rootElements = childElements(in: root)
        let childNames = rootElements.compactMap(\.name)
        let identification = try XCTUnwrap(rootElements.first { $0.name == "identification" })
        let credit = try XCTUnwrap(rootElements.first { $0.name == "credit" })
        let partList = try XCTUnwrap(rootElements.first { $0.name == "part-list" })
        let encoding = try firstXMLChild(named: "encoding", in: identification)
        let software = try firstXMLChild(named: "software", in: encoding)
        let scorePart = try firstXMLChild(named: "score-part", in: partList)
        let partName = try firstXMLChild(named: "part-name", in: scorePart)
        let creditWords = try firstXMLChild(named: "credit-words", in: credit)
        let part = try XCTUnwrap(rootElements.first { $0.name == "part" })
        let measures = part.elements(forName: "measure")
        let firstMeasure = try XCTUnwrap(measures.first { $0.attribute(forName: "number")?.stringValue == "1" })
        let changedTimeSignatureMeasure = try XCTUnwrap(measures.first { measure in
            guard let attributes = measure.elements(forName: "attributes").first,
                  let time = attributes.elements(forName: "time").first else {
                return false
            }
            return time.elements(forName: "beats").first?.stringValue == "3"
        })
        let firstMeasureHarmonies = firstMeasure.elements(forName: "harmony")
        let cMajorSeventhHarmony = try XCTUnwrap(firstMeasureHarmonies.first { harmony in
            harmony.elements(forName: "kind").first?.attribute(forName: "text")?.stringValue == "Cmaj7"
        })
        let alteredHarmony = try XCTUnwrap(firstMeasureHarmonies.first { harmony in
            guard let root = harmony.elements(forName: "root").first,
                  let kind = harmony.elements(forName: "kind").first else {
                return false
            }
            return root.elements(forName: "root-step").first?.stringValue == "B"
                && kind.stringValue == "dominant-13th"
        })
        let regionDirection = try XCTUnwrap(measures.lazy
            .flatMap { $0.elements(forName: "direction") }
            .first { direction in
                guard let directionType = direction.elements(forName: "direction-type").first else {
                    return false
                }
                return directionType.elements(forName: "words").first?.stringValue == "Verse"
            })
        let metronomeDirection = try XCTUnwrap(firstMeasure.elements(forName: "direction").first { direction in
            guard let directionType = direction.elements(forName: "direction-type").first else {
                return false
            }
            return !directionType.elements(forName: "metronome").isEmpty
        })
        let firstMeasureRest = try XCTUnwrap(firstMeasure.elements(forName: "note").first { note in
            note.elements(forName: "rest").first?.attribute(forName: "measure")?.stringValue == "yes"
        })

        XCTAssertTrue(xml.contains("<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">"))
        XCTAssertEqual(root.name, "score-partwise")
        XCTAssertEqual(root.attribute(forName: "version")?.stringValue, "4.0")
        XCTAssertEqual(software.stringValue, "JammLab 9.8.7")
        try assertXMLChild(identification, precedes: credit, in: root)
        XCTAssertLessThan(
            try XCTUnwrap(childNames.firstIndex(of: "credit")),
            try XCTUnwrap(childNames.firstIndex(of: "part-list"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(childNames.firstIndex(of: "part-list")),
            try XCTUnwrap(childNames.firstIndex(of: "part"))
        )
        XCTAssertEqual(credit.attribute(forName: "page")?.stringValue, "1")
        XCTAssertEqual(credit.elements(forName: "credit-type").first?.stringValue, "title")
        XCTAssertEqual(creditWords.stringValue, "Song")
        XCTAssertEqual(creditWords.attribute(forName: "default-x")?.stringValue, "600.17")
        XCTAssertEqual(creditWords.attribute(forName: "default-y")?.stringValue, "1611.01")
        XCTAssertEqual(creditWords.attribute(forName: "justify")?.stringValue, "center")
        XCTAssertEqual(creditWords.attribute(forName: "valign")?.stringValue, "top")
        XCTAssertEqual(creditWords.attribute(forName: "font-size")?.stringValue, "22")
        XCTAssertEqual(partName.stringValue, "Song")
        XCTAssertEqual(partName.attribute(forName: "print-object")?.stringValue, "no")
        XCTAssertEqual(firstMeasure.attribute(forName: "number")?.stringValue, "1")

        let firstMeasureAttributes = try firstXMLChild(named: "attributes", in: firstMeasure)
        let metronomeDirectionType = try firstXMLChild(named: "direction-type", in: metronomeDirection)
        let metronome = try firstXMLChild(named: "metronome", in: metronomeDirectionType)
        let firstMeasureKey = try firstXMLChild(named: "key", in: firstMeasureAttributes)
        XCTAssertEqual(try firstXMLChild(named: "fifths", in: firstMeasureKey).stringValue, "1")
        XCTAssertEqual(try firstXMLChild(named: "beat-unit", in: metronome).stringValue, "quarter")
        XCTAssertEqual(try firstXMLChild(named: "per-minute", in: metronome).stringValue, "120")
        try assertXMLChild(firstMeasureAttributes, precedes: metronomeDirection, in: firstMeasure)

        let changedTimeSignatureAttributes = try firstXMLChild(named: "attributes", in: changedTimeSignatureMeasure)
        let changedTimeSignature = try firstXMLChild(named: "time", in: changedTimeSignatureAttributes)
        XCTAssertEqual(try firstXMLChild(named: "beats", in: changedTimeSignature).stringValue, "3")

        let cMajorSeventhRoot = try firstXMLChild(named: "root", in: cMajorSeventhHarmony)
        let cMajorSeventhKind = try firstXMLChild(named: "kind", in: cMajorSeventhHarmony)
        XCTAssertEqual(try firstXMLChild(named: "root-step", in: cMajorSeventhRoot).stringValue, "C")
        XCTAssertTrue(cMajorSeventhRoot.elements(forName: "root-alter").isEmpty)
        XCTAssertEqual(cMajorSeventhKind.attribute(forName: "text")?.stringValue, "Cmaj7")
        XCTAssertEqual(cMajorSeventhKind.stringValue, "major-seventh")
        XCTAssertEqual(try firstXMLChild(named: "offset", in: cMajorSeventhHarmony).stringValue, "0")

        let alteredRoot = try firstXMLChild(named: "root", in: alteredHarmony)
        let alteredDegree = try firstXMLChild(named: "degree", in: alteredHarmony)
        let alteredBass = try firstXMLChild(named: "bass", in: alteredHarmony)
        XCTAssertEqual(try firstXMLChild(named: "root-step", in: alteredRoot).stringValue, "B")
        XCTAssertEqual(try firstXMLChild(named: "root-alter", in: alteredRoot).stringValue, "-1")
        XCTAssertEqual(try firstXMLChild(named: "degree-value", in: alteredDegree).stringValue, "11")
        XCTAssertEqual(try firstXMLChild(named: "bass-step", in: alteredBass).stringValue, "D")
        XCTAssertTrue(alteredBass.elements(forName: "bass-alter").isEmpty)
        XCTAssertEqual(try firstXMLChild(named: "offset", in: alteredHarmony).stringValue, "1440")
        try assertXMLChild(alteredHarmony, precedes: firstMeasureRest, in: firstMeasure)

        let regionDirectionType = try firstXMLChild(named: "direction-type", in: regionDirection)
        let regionWords = try firstXMLChild(named: "words", in: regionDirectionType)
        XCTAssertEqual(regionWords.stringValue, "Verse")
        XCTAssertEqual(regionWords.attribute(forName: "enclosure")?.stringValue, "rectangle")
        XCTAssertEqual(regionWords.attribute(forName: "font-weight")?.stringValue, "bold")
        let rest = try firstXMLChild(named: "rest", in: firstMeasureRest)
        XCTAssertEqual(rest.attribute(forName: "measure")?.stringValue, "yes")
        XCTAssertEqual(try firstXMLChild(named: "type", in: firstMeasureRest).stringValue, "whole")
    }

    func testMusicXMLExportFailsForUnsupportedHarmony() throws {
        let state = NotationViewportFactory().scoreState(
            tempoMap: fourFourTempoMap(duration: 4),
            duration: 4,
            currentTime: 0,
            playbackMarkerTime: 0,
            isPlaying: false,
            keyName: "C major",
            harmonySymbols: [
                HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "G7alt")
            ]
        )

        XCTAssertThrowsError(
            try NotationExportService().export(
                NotationExportRequest(displayName: "Song", score: state),
                format: .musicXML
            )
        ) { error in
            XCTAssertEqual(error as? NotationExportError, .unsupportedChord(rawText: "G7alt", measureNumber: 1))
        }
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

    private func fourFourTempoMap(
        duration: TimeInterval,
        firstBeatTime: TimeInterval = 0,
        markers: [TimecodedNote] = []
    ) -> TempoMap {
        TempoMap(
            baseSettings: BeatGridSettings(
                bpm: 120,
                firstBeatTime: firstBeatTime,
                timeSignature: .fourFour
            ),
            markers: markers,
            duration: duration
        )
    }

    private func timeSignatureMarker(
        time: TimeInterval,
        beatsPerBar: Int,
        setsNewFirstBeat: Bool = false
    ) -> TimecodedNote {
        TimecodedNote(
            time: time,
            title: "\(beatsPerBar)/4",
            metadata: TempoTimeSignatureMarkerPayload(
                beatsPerBar: beatsPerBar,
                setsNewFirstBeat: setsNewFirstBeat
            ).metadata
        )
    }
}
