import Foundation
import XCTest
@testable import JammLab

final class NotationMusicXMLErrorTests: XCTestCase {
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
