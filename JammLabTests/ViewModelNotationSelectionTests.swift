import XCTest
@testable import JammLab

final class ViewModelNotationSelectionTests: XCTestCase {
    @MainActor
    func testSelectingNotationMeasureAtCurrentMarkerDoesNotMarkProjectModified() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)

        viewModel.selectNotationMeasure(measure)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertEqual(viewModel.playbackMarkerTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertTrue(viewModel.canCopySelectedNotationMeasure)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationMeasureMovesPlaybackMarkerExactlyToMeasureStart() throws {
        let engine = MockPlaybackEngine()
        let viewModel = try loadedNotationViewModel(duration: 8, playbackEngine: engine)
        viewModel.isSnapEnabled = true
        let measure = try notationMeasure(2, in: viewModel)

        viewModel.selectNotationMeasure(measure)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2])
        XCTAssertEqual(viewModel.playbackMarkerTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isProjectModified)
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
    func testSelectingNotationNoteAuditionsWhenRequested() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        let pitch = NotationPitch(step: .e, octave: 4)
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "selected-note",
                kind: .note,
                pitch: pitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "rest",
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 1,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        let measure = try notationMeasure(1, in: viewModel)
        let note = try XCTUnwrap(measure.notationItems.first { $0.id == "selected-note" })
        let rest = try XCTUnwrap(measure.notationItems.first { $0.id == "rest" })

        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: note),
            shouldAudition: true
        )
        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: note),
            shouldAudition: true
        )
        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: rest),
            shouldAudition: true
        )
        viewModel.clearNotationItemSelection()

        XCTAssertEqual(auditioner.auditionedPitches, [pitch, pitch])
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationNoteDoesNotAuditionWhenSuppressed() throws {
        let auditioner = MockNotationNoteAuditioner()
        let viewModel = try loadedNotationViewModel(
            duration: 8,
            notationNoteAuditioner: auditioner
        )
        viewModel.notationItems = [
            NotationMeasureItem(
                id: "selected-note",
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 4),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        viewModel.markProjectClean()
        let measure = try notationMeasure(1, in: viewModel)
        let note = try XCTUnwrap(measure.notationItems.first { $0.id == "selected-note" })

        viewModel.selectNotationItem(
            NotationItemSelection(measure: measure, item: note),
            shouldAudition: false
        )

        XCTAssertTrue(auditioner.auditionedPitches.isEmpty)
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
    func testShiftSelectingNotationMeasuresBuildsContiguousRange() throws {
        let engine = MockPlaybackEngine()
        let viewModel = try loadedNotationViewModel(duration: 10, playbackEngine: engine)
        let secondMeasure = try notationMeasure(2, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)

        viewModel.selectNotationMeasure(secondMeasure)
        viewModel.selectNotationMeasure(fourthMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2, 3, 4])
        XCTAssertEqual(viewModel.playbackMarkerTime, secondMeasure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, secondMeasure.startTime, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, secondMeasure.startTime, accuracy: 0.0001)

        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2])
    }

    @MainActor
    func testReverseShiftSelectingNotationMeasuresMovesMarkerToFirstSelectedMeasure() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)

        viewModel.selectNotationMeasure(thirdMeasure)

        XCTAssertEqual(viewModel.playbackMarkerTime, thirdMeasure.startTime, accuracy: 0.0001)

        viewModel.selectNotationMeasure(firstMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1, 2, 3])
        XCTAssertEqual(viewModel.playbackMarkerTime, firstMeasure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, firstMeasure.startTime, accuracy: 0.0001)
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

    @MainActor
    func testClearingNotationMeasureSelectionDoesNotMovePlaybackMarker() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(2, in: viewModel)
        viewModel.selectNotationMeasure(measure)
        viewModel.markProjectClean()

        viewModel.clearNotationMeasureSelection()

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertEqual(viewModel.playbackMarkerTime, measure.startTime, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, measure.startTime, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }

}

extension XCTestCase {
    @MainActor
    func loadedNotationViewModel(
        duration: TimeInterval,
        playbackEngine: MockPlaybackEngine? = nil,
        notationNoteAuditioner: NotationNoteAuditioning? = nil
    ) throws -> AudioPlayerViewModel {
        let audioURL = try temporaryAudioFile(duration: duration)
        let playbackEngine = playbackEngine ?? MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: playbackEngine,
            notationNoteAuditioner: notationNoteAuditioner ?? NoopNotationNoteAuditioner()
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
