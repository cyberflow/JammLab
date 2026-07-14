import Foundation
import XCTest
@testable import JammLab

final class ViewModelNotationExportTests: XCTestCase {
    @MainActor
    func testExportNotationWritesMusicXMLWithoutChangingDirtyOrUndoState() async throws {
        let emptyViewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        XCTAssertFalse(emptyViewModel.canExportNotation)

        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.tempoBPM = 132.5
        viewModel.beatGridSettings.bpm = 132.5
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "Cmaj7")
        ]
        viewModel.markProjectClean()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notation-export-\(UUID().uuidString)")
            .appendingPathExtension("musicxml")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        XCTAssertTrue(viewModel.canExportNotation)
        let didExportCleanProject = await viewModel.exportNotation(format: .musicXML, to: outputURL)

        XCTAssertTrue(didExportCleanProject)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertNil(viewModel.errorMessage)
        let xml = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(xml.contains("<score-partwise version=\"4.0\">"))
        XCTAssertTrue(xml.contains("<kind text=\"Cmaj7\">major-seventh</kind>"))
        XCTAssertTrue(xml.contains("<per-minute>132.5</per-minute>"))

        viewModel.setLooping(true)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertTrue(viewModel.canUndo)

        let didExportDirtyProject = await viewModel.exportNotation(format: .musicXML, to: outputURL)

        XCTAssertTrue(didExportDirtyProject)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testViewModelExportIncludesStemPartAndWritesRegionOnce() async throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "bass-note",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.notes = [
            TimecodedNote(kind: .region, time: 0.5, duration: 2, title: "Intro")
        ]
        viewModel.visibleNotationPartIDs = [.main, .stem(.bass)]
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notation-stem-export-\(UUID().uuidString)")
            .appendingPathExtension("musicxml")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let didExport = await viewModel.exportNotation(format: .musicXML, to: outputURL)
        XCTAssertTrue(didExport)

        let xml = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(xml.contains("<part-name>Bass Guitar</part-name>"))
        XCTAssertTrue(xml.contains("<step>E</step>"))
        XCTAssertEqual(xml.components(separatedBy: ">Intro</words>").count - 1, 1)
    }

    @MainActor
    func testViewModelExportIncludesOnlyPartsSelectedInNotationWindow() async throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "main-note",
                partID: .main,
                kind: .note,
                pitch: NotationPitch(step: .c, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "bass-note",
                partID: .stem(.bass),
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C")
        ]
        viewModel.notes = [
            TimecodedNote(kind: .region, time: 0.5, duration: 2, title: "Intro")
        ]
        viewModel.visibleNotationPartIDs = [.stem(.bass)]
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notation-selected-parts-export-\(UUID().uuidString)")
            .appendingPathExtension("musicxml")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        XCTAssertTrue(viewModel.canExportNotation)
        let didExport = await viewModel.exportNotation(format: .musicXML, to: outputURL)
        XCTAssertTrue(didExport)

        let data = try Data(contentsOf: outputURL)
        let document = try XMLDocument(data: data)
        let root = try XCTUnwrap(document.rootElement())
        let partList = try XCTUnwrap(root.elements(forName: "part-list").first)
        let scoreParts = partList.elements(forName: "score-part")
        let bassScorePart = try XCTUnwrap(scoreParts.first)
        let scoreInstrument = try XCTUnwrap(bassScorePart.elements(forName: "score-instrument").first)
        let parts = root.elements(forName: "part")
        let measures = try XCTUnwrap(parts.first).elements(forName: "measure")

        XCTAssertEqual(scoreParts.count, 1)
        XCTAssertEqual(bassScorePart.elements(forName: "part-name").first?.stringValue, "Bass Guitar")
        XCTAssertEqual(bassScorePart.elements(forName: "part-abbreviation").first?.stringValue, "B. Guit.")
        XCTAssertEqual(scoreInstrument.attribute(forName: "id")?.stringValue, "P1-I1")
        XCTAssertEqual(scoreInstrument.elements(forName: "instrument-name").first?.stringValue, "Bass Guitar")
        XCTAssertEqual(scoreInstrument.elements(forName: "instrument-sound").first?.stringValue, "pluck.bass")
        XCTAssertFalse(bassScorePart.stringValue?.contains("Main") == true)
        XCTAssertEqual(parts.count, 1)
        XCTAssertTrue(measures.flatMap { $0.elements(forName: "harmony") }.isEmpty)
        XCTAssertEqual(
            measures.flatMap { $0.elements(forName: "direction") }
                .filter { direction in
                    direction.stringValue?.contains("Intro") == true
                }
                .count,
            1
        )
    }
}
