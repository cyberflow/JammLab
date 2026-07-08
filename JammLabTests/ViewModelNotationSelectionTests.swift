import XCTest
@testable import JammLab

final class ViewModelNotationSelectionTests: XCTestCase {
    @MainActor
    func testSelectingNotationMeasureDoesNotMarkProjectModified() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)

        viewModel.selectNotationMeasure(measure)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertTrue(viewModel.canCopySelectedNotationMeasure)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationItemDoesNotMarkProjectModifiedAndClearsMeasureSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)

        viewModel.selectNotationMeasure(measure)
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertEqual(viewModel.selectedNotationItem?.measureNumber, 1)
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 0)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testRequestEditSelectedNotationItemUsesExactItemOffsetAndExistingHarmony() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = NotationMeasureItem(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let harmony = HarmonySymbol(
            time: NotationMeasureTiming.time(forQuarterOffset: 1, in: measure),
            measureNumber: measure.number,
            offsetInQuarterNotes: 1,
            rawText: "Fmaj7"
        )
        viewModel.harmonySymbols = [harmony]
        viewModel.notationItems = [item]
        viewModel.markProjectClean()

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let updatedItem = try XCTUnwrap(updatedMeasure.notationItems.first { $0.offsetInQuarterNotes == 1 })
        viewModel.selectNotationItem(NotationItemSelection(measure: updatedMeasure, item: updatedItem))

        XCTAssertTrue(viewModel.requestEditSelectedNotationItem())
        let request = try XCTUnwrap(viewModel.pendingHarmonyEditorRequest)
        XCTAssertEqual(request.time, harmony.time, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedHarmonySymbolID, harmony.id)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNotationItemSelectionClearsForTempoMapAndUndoChanges() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let firstItem = try XCTUnwrap(firstMeasure.notationItems.first)

        viewModel.selectNotationItem(NotationItemSelection(measure: firstMeasure, item: firstItem))
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertNil(viewModel.selectedNotationItem)

        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let updatedItem = try XCTUnwrap(updatedMeasure.notationItems.first)
        viewModel.markProjectClean()
        viewModel.selectNotationItem(NotationItemSelection(measure: updatedMeasure, item: updatedItem))
        viewModel.addNote(at: 0.5)

        XCTAssertNotNil(viewModel.selectedNotationItem)

        viewModel.undoLastEdit()

        XCTAssertNil(viewModel.selectedNotationItem)
    }

    @MainActor
    func testChangingSelectedWholeRestToQuarterCreatesTwoQuartersAndHalfInFourFour() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        viewModel.markProjectClean()

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationDurationDenominator(4)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [4, 4, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [1, 1, 2])
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 0)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testChangingSelectedWholeRestToHalfInThreeFourCreatesHalfAndQuarter() throws {
        let viewModel = try loadedNotationViewModel(duration: 6)
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        viewModel.markProjectClean()

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationDurationDenominator(2)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [2, 4])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [2, 1])
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testShiftSelectingNotationMeasuresBuildsContiguousRange() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)

        viewModel.selectNotationMeasure(firstMeasure)
        viewModel.selectNotationMeasure(thirdMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1, 2, 3])

        viewModel.selectNotationMeasure(firstMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
    }

    @MainActor
    func testShiftSelectingNotationMeasureWithoutAnchorFallsBackToSingleSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let secondMeasure = try notationMeasure(2, in: viewModel)

        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2])
    }

    @MainActor
    func testTempoMapChangesClearSelectedNotationMeasure() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)

        viewModel.selectNotationMeasure(measure)
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
    }

}

extension XCTestCase {
    @MainActor
    func loadedNotationViewModel(duration: TimeInterval) throws -> AudioPlayerViewModel {
        let audioURL = try temporaryAudioFile(duration: duration)
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "notation.wav", duration: duration)
        try viewModel.loadImportedAudio(media)
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        viewModel.tempoBPM = 120
        viewModel.applyTempoMapToPlaybackEngine()
        viewModel.markProjectClean()
        return viewModel
    }

    @MainActor
    func notationMeasure(_ number: Int, in viewModel: AudioPlayerViewModel) throws -> ScoreMeasure {
        let score = NotationViewportFactory().scoreState(
            tempoMap: viewModel.tempoMap,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            isPlaying: viewModel.playbackState == .playing,
            keyName: viewModel.effectiveKeyName,
            notationItems: viewModel.notationItems,
            harmonySymbols: viewModel.harmonySymbols,
            notes: viewModel.notes
        )
        return try XCTUnwrap(score.measures.first { $0.number == number })
    }
}
