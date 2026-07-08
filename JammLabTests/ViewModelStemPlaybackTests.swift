import XCTest
@testable import JammLab

final class ViewModelStemPlaybackTests: XCTestCase {
    @MainActor
    func testViewModelTogglePlaybackModeStaysOriginalWhenStemsUnavailable() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())

        viewModel.togglePlaybackMode()

        XCTAssertEqual(viewModel.playbackMode, .original)
    }

    @MainActor
    func testViewModelSetPlaybackModeStaysOriginalWhenStemsUnavailable() {
        let viewModel = AudioPlayerViewModel(playbackEngine: MockPlaybackEngine())

        viewModel.setPlaybackMode(.stems)

        XCTAssertEqual(viewModel.playbackMode, .original)
    }

    @MainActor
    func testRegisterStemMetadataActivatesStemPlaybackWhenRequested() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12

        viewModel.registerStemMetadata(testStemMetadata(), activatePlayback: true)

        XCTAssertEqual(viewModel.playbackMode, .stems)
        XCTAssertEqual(viewModel.stemFiles.map(\.type), StemSeparationMethod.fourStem.stemTypes)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(engine.mixState.item(for: .vocals).isAvailable)
        XCTAssertEqual(viewModel.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
    }

    @MainActor
    func testRegisterStemMetadataPreservesPlayingPositionWhenActivatingStems() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12
        viewModel.playbackMarkerTime = 2
        viewModel.playbackState = .playing
        engine.isLoaded = true
        engine.isPlaying = true
        engine.currentTime = 12

        viewModel.registerStemMetadata(testStemMetadata(), activatePlayback: true)

        XCTAssertEqual(viewModel.playbackMode, .stems)
        XCTAssertEqual(viewModel.playbackState, .playing)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(viewModel.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
        XCTAssertEqual(viewModel.playbackMarkerTime, 2, accuracy: 0.0001)
    }

    @MainActor
    func testRegisterStemMetadataDoesNotActivateStemPlaybackByDefault() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12

        viewModel.registerStemMetadata(testStemMetadata())

        XCTAssertEqual(viewModel.playbackMode, .original)
        XCTAssertEqual(viewModel.stemFiles.map(\.type), StemSeparationMethod.fourStem.stemTypes)
        XCTAssertFalse(engine.isLoaded)
    }

    @MainActor
    func testRegisterStemMetadataLoadsPlaybackWhenProjectRestoresStemMode() {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        viewModel.duration = 30
        viewModel.currentTime = 12
        viewModel.playbackMode = .stems

        viewModel.registerStemMetadata(testStemMetadata())

        XCTAssertEqual(viewModel.playbackMode, .stems)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(engine.mixState.item(for: .drums).isAvailable)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
    }

    private func testStemMetadata() -> StemCacheMetadata {
        StemCacheMetadata(
            cacheKey: "test-cache",
            sourceFingerprint: StemSourceFingerprint(path: "/tmp/song.wav", fileSize: 42, modificationTime: 10),
            backendIdentifier: "test-backend",
            separationMethodID: StemSeparationMethod.fourStem.id,
            modelName: StemSeparationMethod.fourStem.modelName,
            settingsVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            stems: StemSeparationMethod.fourStem.stemTypes.map { type in
                StemFile(
                    type: type,
                    url: URL(fileURLWithPath: "/tmp/\(type.canonicalStemFilename)"),
                    displayName: type.title
                )
            }
        )
    }
}
