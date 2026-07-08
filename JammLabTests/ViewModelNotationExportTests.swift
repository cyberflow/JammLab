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
}
