import XCTest
@testable import JammLab

final class ViewModelTempoMapTests: XCTestCase {
    @MainActor
    func testAddingTempoTimeSignatureMarkerUpdatesPlaybackTempoMap() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 60, beatsPerBar: 3)

        let marker = try XCTUnwrap(viewModel.notes.first)
        let payload = try XCTUnwrap(marker.tempoTimeSignaturePayload)
        let tempoMap = try XCTUnwrap(engine.tempoMap)

        XCTAssertTrue(marker.isTempoTimeSignatureMarker)
        XCTAssertEqual(marker.title, "60 BPM · 3/4")
        XCTAssertEqual(try XCTUnwrap(payload.bpm), 60, accuracy: 0.0001)
        XCTAssertEqual(payload.beatsPerBar, 3)
        XCTAssertFalse(payload.setsNewFirstBeat)
        XCTAssertEqual(tempoMap.segments.count, 2)
        XCTAssertEqual(tempoMap.segments[1].startTime, 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(tempoMap.segments[1].settings.bpm), 60, accuracy: 0.0001)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 2)
        XCTAssertEqual(tempoMap.segments[1].settings.timeSignature, TimeSignature(beatsPerBar: 3, beatUnit: 4))
    }

    @MainActor
    func testTransportPositionTextUsesCurrentTempoMap() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(
            at: 2,
            bpm: 120,
            beatsPerBar: 3,
            setsNewFirstBeat: false
        )
        viewModel.currentTime = 3.5

        XCTAssertEqual(viewModel.transportPositionText, "3.1.00 / 0:03.500")
    }

    @MainActor
    func testAddingNewFirstBeatOnlyMarkerUpdatesPlaybackTempoMap() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(
            at: 2,
            bpm: 120,
            beatsPerBar: 4,
            setsNewFirstBeat: true
        )

        let marker = try XCTUnwrap(viewModel.notes.first)
        let payload = try XCTUnwrap(marker.tempoTimeSignaturePayload)
        let tempoMap = try XCTUnwrap(engine.tempoMap)

        XCTAssertEqual(marker.title, "New First Beat")
        XCTAssertTrue(payload.setsNewFirstBeat)
        XCTAssertNil(payload.bpm)
        XCTAssertNil(payload.beatsPerBar)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 1)
    }

    @MainActor
    func testEditingTempoTimeSignatureMarkerBackToEffectiveSettingsRemovesNoOpMarker() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 60, beatsPerBar: 3)
        let marker = try XCTUnwrap(viewModel.notes.first)

        viewModel.updateTempoTimeSignatureMarker(id: marker.id, bpm: 120, beatsPerBar: 4)

        let updatedTempoMap = try XCTUnwrap(engine.tempoMap)
        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertEqual(updatedTempoMap.segments.count, 1)
        XCTAssertEqual(try XCTUnwrap(updatedTempoMap.segments.first?.settings.bpm), 120, accuracy: 0.0001)
    }

    @MainActor
    func testEditingTempoTimeSignatureMarkerUpdatesNewFirstBeatFlag() throws {
        let audioURL = try temporaryAudioFile(duration: 6)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "tempo.wav", duration: 6)
        try viewModel.loadImportedAudio(media)

        viewModel.setTempoBPM(120)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 60, beatsPerBar: 3)
        let marker = try XCTUnwrap(viewModel.notes.first)

        viewModel.updateTempoTimeSignatureMarker(
            id: marker.id,
            bpm: 60,
            beatsPerBar: 3,
            setsNewFirstBeat: true
        )

        let updatedMarker = try XCTUnwrap(viewModel.notes.first)
        let payload = try XCTUnwrap(updatedMarker.tempoTimeSignaturePayload)
        let tempoMap = try XCTUnwrap(engine.tempoMap)
        XCTAssertTrue(payload.setsNewFirstBeat)
        XCTAssertEqual(tempoMap.segments[1].firstBarNumber, 1)
    }
}
