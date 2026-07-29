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

    @MainActor
    func testRegisterStemMetadataPreparesMultiTrackPlaybackAsynchronously() async {
        let engine = MultiTrackAudioPlayer()
        let viewModel = AudioPlayerViewModel(
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            playbackPreparer: SuspendedStemPlaybackPreparer()
        )
        viewModel.duration = 30
        viewModel.currentTime = 12
        viewModel.importedFile = ImportedAudioFile(
            url: URL(fileURLWithPath: "/tmp/original.wav"),
            displayName: "original.wav",
            duration: 30
        )

        viewModel.registerStemMetadata(testStemMetadata(), activatePlayback: true)
        await Task.yield()

        XCTAssertEqual(viewModel.playbackMode, .original)
        XCTAssertNotNil(viewModel.audioPreparationTask)
        XCTAssertEqual(viewModel.audioPreparationState.kind, .switchingMode)
        XCTAssertEqual(viewModel.audioPreparationState.pendingPlaybackMode, .stems)
        XCTAssertFalse(engine.isLoaded)

        viewModel.cancelAudioPreparation()
        let didCancel = await waitForMainActorCondition {
            viewModel.audioPreparationTask == nil
        }
        XCTAssertTrue(didCancel)
    }

    @MainActor
    func testPreparedModeInstallFailureRestoresOriginalPlayback() async {
        let engine = MockPlaybackEngine()
        engine.requiresPreparedPlayback = true
        let viewModel = AudioPlayerViewModel(
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            playbackPreparer: ImmediatePlaybackPreparer()
        )
        let originalURL = URL(fileURLWithPath: "/tmp/original.wav")
        viewModel.importedFile = ImportedAudioFile(
            url: originalURL,
            displayName: "original.wav",
            duration: 30
        )
        viewModel.duration = 30
        viewModel.currentTime = 12
        viewModel.playbackState = .playing
        viewModel.registerStemMetadata(testStemMetadata())
        viewModel.preparedPlaybackAssets[.original] = PreparedPlaybackAsset(storage: .originalURL(originalURL))
        engine.isLoaded = true
        engine.isPlaying = true
        engine.currentTime = 12
        engine.queuedLoadErrors = [TestStemPlaybackError.installFailed]

        viewModel.setPlaybackMode(.stems)
        let didFinish = await waitForMainActorCondition {
            viewModel.audioPreparationTask == nil
        }

        XCTAssertTrue(didFinish)
        XCTAssertEqual(viewModel.playbackMode, .original)
        XCTAssertEqual(viewModel.playbackState, .playing)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
        XCTAssertFalse(viewModel.canUndo)
    }

    @MainActor
    func testReplacingActiveStemsFallsBackToOriginalWhenInstallFails() async {
        let engine = MockPlaybackEngine()
        engine.requiresPreparedPlayback = true
        let viewModel = AudioPlayerViewModel(
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            playbackPreparer: ImmediatePlaybackPreparer()
        )
        let originalURL = URL(fileURLWithPath: "/tmp/original.wav")
        viewModel.importedFile = ImportedAudioFile(
            url: originalURL,
            displayName: "original.wav",
            duration: 30
        )
        viewModel.duration = 30
        viewModel.currentTime = 9
        viewModel.registerStemMetadata(testStemMetadata())
        viewModel.playbackMode = .stems
        viewModel.preparedPlaybackAssets[.original] = PreparedPlaybackAsset(storage: .originalURL(originalURL))
        viewModel.preparedPlaybackAssets[.stems] = PreparedPlaybackAsset(
            storage: .stems(viewModel.stemFiles, viewModel.stemMixState)
        )
        viewModel.playbackState = .playing
        engine.isLoaded = true
        engine.isPlaying = true
        engine.currentTime = 9
        engine.queuedLoadErrors = [TestStemPlaybackError.installFailed]

        viewModel.registerStemMetadata(testStemMetadata(), activatePlayback: true)
        let didFinish = await waitForMainActorCondition {
            viewModel.audioPreparationTask == nil
        }

        XCTAssertTrue(didFinish)
        XCTAssertEqual(viewModel.playbackMode, .original)
        XCTAssertEqual(viewModel.playbackState, .playing)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 9, accuracy: 0.0001)
        XCTAssertEqual(viewModel.stemSeparationState.phase, .completed)
    }

    @MainActor
    func testPreparedModeInstallAndRecoveryFailurePausesPlaybackWithDiagnostics() async {
        let engine = MockPlaybackEngine()
        engine.requiresPreparedPlayback = true
        let viewModel = AudioPlayerViewModel(
            peakformProvider: MockPeakformProvider(),
            playbackEngine: engine,
            playbackPreparer: ImmediatePlaybackPreparer()
        )
        let originalURL = URL(fileURLWithPath: "/tmp/original.wav")
        viewModel.importedFile = ImportedAudioFile(
            url: originalURL,
            displayName: "original.wav",
            duration: 30
        )
        viewModel.duration = 30
        viewModel.currentTime = 7
        viewModel.playbackState = .playing
        viewModel.registerStemMetadata(testStemMetadata())
        viewModel.preparedPlaybackAssets[.original] = PreparedPlaybackAsset(storage: .originalURL(originalURL))
        engine.isLoaded = true
        engine.isPlaying = true
        engine.queuedLoadErrors = [
            TestStemPlaybackError.installFailed,
            TestStemPlaybackError.recoveryFailed
        ]

        viewModel.setPlaybackMode(.stems)
        let didFinish = await waitForMainActorCondition {
            viewModel.audioPreparationTask == nil
        }

        XCTAssertTrue(didFinish)
        XCTAssertEqual(viewModel.playbackMode, .original)
        XCTAssertEqual(viewModel.playbackState, .paused)
        XCTAssertFalse(engine.isLoaded)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertTrue(
            viewModel.errorMessage?.contains("Previous playback could not be restored") == true,
            viewModel.errorMessage ?? "Expected recovery diagnostics, got nil"
        )
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

private struct SuspendedStemPlaybackPreparer: AudioPlaybackPreparing {
    func prepareOriginal(
        url: URL,
        volume: Float,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        PreparedPlaybackAsset(storage: .originalURL(url))
    }

    func prepareStems(
        _ stems: [StemFile],
        mixState: StemMixState,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        try await Task.sleep(nanoseconds: 10_000_000_000)
        return PreparedPlaybackAsset(storage: .stems(stems, mixState))
    }
}

private struct ImmediatePlaybackPreparer: AudioPlaybackPreparing {
    func prepareOriginal(
        url: URL,
        volume: Float,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        PreparedPlaybackAsset(storage: .originalURL(url))
    }

    func prepareStems(
        _ stems: [StemFile],
        mixState: StemMixState,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        PreparedPlaybackAsset(storage: .stems(stems, mixState))
    }
}

private enum TestStemPlaybackError: LocalizedError {
    case installFailed
    case recoveryFailed

    var errorDescription: String? {
        switch self {
        case .installFailed:
            return "install failed"
        case .recoveryFailed:
            return "recovery failed"
        }
    }
}
