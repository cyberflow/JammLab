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
