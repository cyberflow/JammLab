import XCTest
@testable import JammLab

final class ViewModelNoteEditingTests: XCTestCase {
    @MainActor
    func testUndoRestoresNoteUpdateOrderAndTitle() {
        let undoManager = UndoManager()
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        let markerA = TimecodedNote(time: 10, title: "A")
        let markerB = TimecodedNote(time: 2, title: "B")
        let state = ProjectEditableState(
            notes: [markerA, markerB],
            selectedRegionID: nil,
            activeLoopRegionID: nil,
            loopRegion: .empty,
            isLooping: false,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            mainTrackVolume: AppSliderDefaults.mainTrackVolume,
            stemMixState: StemMixState(),
            playbackMode: .original,
            isClickEnabled: false,
            clickVolume: AppSliderDefaults.clickVolume,
            isSnapEnabled: false
        )
        viewModel.restoreEditableState(state)
        viewModel.undoManager = undoManager

        viewModel.updateNoteTitle(id: markerA.id, title: "Renamed")

        XCTAssertEqual(viewModel.notes.map(\.title), ["Renamed", "B"])

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.notes.map(\.title), ["A", "B"])
    }

    @MainActor
    func testViewModelUpdatesPresetAndCustomNoteColors() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())
        let marker = TimecodedNote(time: 2, title: "A", color: .markerBlue, customColorHex: "#123456")
        let state = ProjectEditableState(
            notes: [marker],
            selectedRegionID: nil,
            activeLoopRegionID: nil,
            loopRegion: .empty,
            isLooping: false,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            mainTrackVolume: AppSliderDefaults.mainTrackVolume,
            stemMixState: StemMixState(),
            playbackMode: .original,
            isClickEnabled: false,
            clickVolume: AppSliderDefaults.clickVolume,
            isSnapEnabled: false
        )
        viewModel.restoreEditableState(state)

        viewModel.updateNoteCustomColor(id: marker.id, hex: "abcdef")

        XCTAssertEqual(viewModel.notes.first?.customColorHex, "#ABCDEF")
        XCTAssertEqual(viewModel.notes.first?.resolvedColorHex, "#ABCDEF")

        viewModel.updateNoteColor(id: marker.id, color: .markerOrange)

        XCTAssertEqual(viewModel.notes.first?.color, .markerOrange)
        XCTAssertNil(viewModel.notes.first?.customColorHex)
        XCTAssertEqual(viewModel.notes.first?.resolvedColorHex, MarkerColor.markerOrange.defaultHex)
    }
}
