import XCTest
@testable import JammLab

final class NotationKeySignatureTests: XCTestCase {
    func testNotationKeySignatureParsingSupportsCommonDetectedKeysAndFallback() {
        let fSharpMinor = KeySignature.normalized(from: "F# minor")
        let bFlatMajor = KeySignature.normalized(from: "Bb major")
        let aMinor = KeySignature.normalized(from: "Am")
        let fallback = KeySignature.normalized(from: "Pending")

        XCTAssertEqual(fSharpMinor.fifths, 3)
        XCTAssertEqual(fSharpMinor.mode, .minor)
        XCTAssertEqual(bFlatMajor.fifths, -2)
        XCTAssertEqual(bFlatMajor.mode, .major)
        XCTAssertEqual(aMinor.fifths, 0)
        XCTAssertEqual(aMinor.mode, .minor)
        XCTAssertEqual(fallback, .cMajor)
    }

    func testNotationKeySignatureAccidentalsUseTrebleStaffPositions() {
        let cMajor = KeySignature.normalized(from: "C major")
        let fMinor = KeySignature.normalized(from: "F minor")
        let fSharpMinor = KeySignature.normalized(from: "F# minor")

        XCTAssertTrue(cMajor.notationAccidentalGlyphs(for: .treble).isEmpty)
        XCTAssertEqual(
            fMinor.notationAccidentalGlyphs(for: .treble),
            [
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 4),
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 1),
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 5),
                KeySignatureAccidental(symbol: "♭", staffPositionFromTopLine: 2)
            ]
        )
        XCTAssertEqual(
            fSharpMinor.notationAccidentalGlyphs(for: .treble),
            [
                KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 0),
                KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: 3),
                KeySignatureAccidental(symbol: "♯", staffPositionFromTopLine: -1)
            ]
        )
    }

    func testNotationKeySignatureAccidentalsUseFullTrebleOrder() {
        let cSharpMajor = KeySignature.normalized(from: "C# major")
        let cFlatMajor = KeySignature.normalized(from: "Cb major")
        let cSharpMajorGlyphs = cSharpMajor.notationAccidentalGlyphs(for: .treble)
        let cFlatMajorGlyphs = cFlatMajor.notationAccidentalGlyphs(for: .treble)

        XCTAssertEqual(
            cSharpMajorGlyphs.map(\.staffPositionFromTopLine),
            [0, 3, -1, 2, 5, 1, 4]
        )
        XCTAssertEqual(
            cSharpMajorGlyphs.map(\.symbol),
            Array(repeating: "♯", count: 7)
        )
        XCTAssertEqual(
            cFlatMajorGlyphs.map(\.staffPositionFromTopLine),
            [4, 1, 5, 2, 6, 3, 7]
        )
        XCTAssertEqual(
            cFlatMajorGlyphs.map(\.symbol),
            Array(repeating: "♭", count: 7)
        )
    }

    func testProjectKeySelectionMapsDetectedKeysToToolbarValuesAndCanonicalNames() throws {
        let fSharpMinor = try XCTUnwrap(ProjectKeySelection.detected(from: "F# minor", confidence: 0.82))
        let bFlatMajor = try XCTUnwrap(ProjectKeySelection.detected(from: "Bb major", confidence: 0.76))
        let unknown = ProjectKeySelection.detected(from: "Pending", confidence: 0)

        XCTAssertEqual(fSharpMinor.tonic, .fSharpGb)
        XCTAssertEqual(fSharpMinor.mode, .minor)
        XCTAssertEqual(fSharpMinor.canonicalKeyName, "F# minor")
        XCTAssertEqual(fSharpMinor.source, .auto)
        XCTAssertEqual(try XCTUnwrap(fSharpMinor.confidence), 0.82, accuracy: 0.0001)

        XCTAssertEqual(bFlatMajor.tonic, .aSharpBb)
        XCTAssertEqual(bFlatMajor.mode, .major)
        XCTAssertEqual(bFlatMajor.canonicalKeyName, "Bb major")
        XCTAssertNil(unknown)
    }
}
