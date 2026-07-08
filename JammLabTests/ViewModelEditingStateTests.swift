import XCTest
@testable import JammLab

final class ViewModelEditingStateTests: XCTestCase {
    @MainActor
    func testImportedAudioStartsCleanAndPersistedEditMarksProjectModified() throws {
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "loop.wav", duration: 0.5)

        try viewModel.loadImportedAudio(media)

        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertEqual(viewModel.windowTitle, "loop.wav - JammLab")

        viewModel.setMainTrackVolume(0.2)

        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertEqual(viewModel.windowTitle, "loop.wav [modified] - JammLab")
    }

    @MainActor
    func testUndoRedoLoopingUpdatesModifiedState() throws {
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "loop.wav", duration: 0.5)
        try viewModel.loadImportedAudio(media)
        viewModel.undoManager = undoManager

        viewModel.setLooping(true)

        XCTAssertTrue(viewModel.isLooping)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        XCTAssertFalse(viewModel.isLooping)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        XCTAssertTrue(viewModel.isLooping)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testTimeSignatureChangeUpdatesClickSettingsModifiedStateAndUndo() throws {
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let undoManager = UndoManager()
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "meter.wav", duration: 2)
        try viewModel.loadImportedAudio(media)
        viewModel.undoManager = undoManager

        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertEqual(viewModel.beatGridSettings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
        XCTAssertEqual(engine.clickSettings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.beatGridSettings.timeSignature, .fourFour)
        XCTAssertEqual(engine.clickSettings.timeSignature, .fourFour)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        XCTAssertEqual(viewModel.beatGridSettings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testProjectEditableStateRestoreAppliesEngineBackedSettings() {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        let noteID = TimecodedNote.ID()
        let regionID = TimecodedNote.ID()
        let notes = [
            TimecodedNote(id: noteID, time: 1, title: "Marker A"),
            TimecodedNote(id: regionID, kind: .region, time: 2, duration: 3, title: "Region A", color: .regionGreen)
        ]
        var mix = StemMixState()
        mix.update(.vocals) {
            $0.volume = 0.2
            $0.isMuted = true
        }
        let beatGrid = BeatGridSettings(bpm: 140, firstBeatTime: 0.5, timeSignature: .fourFour)
        let state = ProjectEditableState(
            notes: notes,
            selectedRegionID: regionID,
            activeLoopRegionID: regionID,
            loopRegion: LoopRegion(start: 2, end: 5),
            isLooping: true,
            tempoBPM: 140,
            beatGridSettings: beatGrid,
            playbackRate: 0.5,
            pitchShiftSemitones: -3,
            mainTrackVolume: 0.4,
            stemMixState: mix,
            playbackMode: .original,
            isClickEnabled: true,
            clickVolume: 0.25,
            isSnapEnabled: true
        )

        viewModel.restoreEditableState(state)

        XCTAssertEqual(viewModel.notes.count, 2)
        XCTAssertEqual(viewModel.selectedRegionID, regionID)
        XCTAssertEqual(viewModel.activeLoopRegionID, regionID)
        XCTAssertTrue(viewModel.isLooping)
        XCTAssertEqual(viewModel.playbackRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.pitchShiftSemitones, -3, accuracy: 0.0001)
        XCTAssertEqual(viewModel.mainTrackVolume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.clickVolume, 0.25, accuracy: 0.0001)
        XCTAssertTrue(viewModel.isClickEnabled)
        XCTAssertTrue(viewModel.isSnapEnabled)
        XCTAssertEqual(engine.playbackRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(engine.pitchShiftSemitones, -3, accuracy: 0.0001)
        XCTAssertEqual(engine.mainVolume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(engine.clickVolume, 0.25, accuracy: 0.0001)
        XCTAssertTrue(engine.clickEnabled)
        XCTAssertEqual(try XCTUnwrap(engine.clickSettings.bpm), 140, accuracy: 0.0001)
        XCTAssertTrue(viewModel.stemMixState.item(for: .vocals).isMuted)
    }

    @MainActor
    func testUndoRestoresStemMuteAndRedoReappliesIt() {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        viewModel.undoManager = undoManager

        viewModel.toggleStemMute(.vocals)

        XCTAssertTrue(viewModel.stemMixState.item(for: .vocals).isMuted)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undoLastEdit()

        XCTAssertFalse(viewModel.stemMixState.item(for: .vocals).isMuted)
        XCTAssertTrue(viewModel.canRedo)

        viewModel.redoLastEdit()

        XCTAssertTrue(viewModel.stemMixState.item(for: .vocals).isMuted)
    }

}
