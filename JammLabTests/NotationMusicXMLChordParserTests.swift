import XCTest
@testable import JammLab

final class NotationMusicXMLChordParserTests: XCTestCase {
    func testMusicXMLChordParserSupportsSemanticChords() throws {
        let plain = try MusicXMLChordParser.parse("C", measureNumber: 1)
        XCTAssertEqual(plain.root, MusicXMLPitchStep(step: "C", alter: 0))
        XCTAssertEqual(plain.kindValue, "major")

        let minor = try MusicXMLChordParser.parse("Am", measureNumber: 1)
        XCTAssertEqual(minor.root, MusicXMLPitchStep(step: "A", alter: 0))
        XCTAssertEqual(minor.kindValue, "minor")

        let altered = try MusicXMLChordParser.parse("Bb13(#11)/D", measureNumber: 2)
        XCTAssertEqual(altered.root, MusicXMLPitchStep(step: "B", alter: -1))
        XCTAssertEqual(altered.kindValue, "dominant-13th")
        XCTAssertEqual(altered.bass, MusicXMLPitchStep(step: "D", alter: 0))
        XCTAssertEqual(altered.degrees, [
            MusicXMLChordDegree(value: 11, alter: 1, type: .alter)
        ])

        let halfDiminished = try MusicXMLChordParser.parse("C#m7b5", measureNumber: 3)
        XCTAssertEqual(halfDiminished.root, MusicXMLPitchStep(step: "C", alter: 1))
        XCTAssertEqual(halfDiminished.kindValue, "half-diminished")

        let added = try MusicXMLChordParser.parse("Aadd9", measureNumber: 4)
        XCTAssertEqual(added.kindValue, "major")
        XCTAssertEqual(added.degrees, [
            MusicXMLChordDegree(value: 9, alter: 0, type: .add)
        ])
    }

    func testMusicXMLChordParserRejectsUnsupportedChords() {
        XCTAssertThrowsError(try MusicXMLChordParser.parse("", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("H7", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("G7alt", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("C(foo)", measureNumber: 1))
        XCTAssertThrowsError(try MusicXMLChordParser.parse("C/G/B", measureNumber: 1))
    }
}
