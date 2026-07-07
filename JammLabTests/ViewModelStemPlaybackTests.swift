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
    func testCancelledStemSeparationDoesNotOverwriteCancelledStateWhenTaskFinishesLater() async throws {
        let audioURL = try temporaryAudioFile(duration: 1, namePrefix: "stems")
        let supportDirectory = temporaryDirectory()
        let jobsDirectory = StemJobFiles.currentJobsDirectory(in: supportDirectory)
        try FileManager.default.createDirectory(at: jobsDirectory, withIntermediateDirectories: true)
        try writeHeartbeat(
            to: jobsDirectory.appendingPathComponent(StemJobFiles.heartbeatFilename),
            updatedAt: Date()
        )
        defer {
            try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: supportDirectory)
        }

        let service = StemSeparationService(
            appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false },
            applicationSupportDirectory: supportDirectory
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            stemSeparationService: service
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "stems.caf", duration: 1)
        try viewModel.loadImportedAudio(media)

        viewModel.separateStems()
        try await Task.sleep(nanoseconds: 100_000_000)

        viewModel.cancelStemSeparation()
        try await Task.sleep(nanoseconds: 700_000_000)

        if case .cancelled = viewModel.stemSeparationState.phase {
        } else {
            XCTFail("Expected cancelled stem separation phase, got \(viewModel.stemSeparationState.phase)")
        }
        XCTAssertEqual(viewModel.stemSeparationState.status, "Stem separation cancelled")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.stemSeparationTask)
        XCTAssertNil(viewModel.stemSeparationRunID)
        XCTAssertTrue(viewModel.stemFiles.isEmpty)
    }

    @MainActor
    func testStemSeparationRestartIsBlockedUntilCancelledTaskFinishes() async throws {
        let audioURL = try temporaryAudioFile(duration: 1, namePrefix: "stems-restart")
        let supportDirectory = temporaryDirectory()
        let jobsDirectory = StemJobFiles.currentJobsDirectory(in: supportDirectory)
        try FileManager.default.createDirectory(at: jobsDirectory, withIntermediateDirectories: true)
        try writeHeartbeat(
            to: jobsDirectory.appendingPathComponent(StemJobFiles.heartbeatFilename),
            updatedAt: Date()
        )
        defer {
            try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: supportDirectory)
        }

        let service = StemSeparationService(
            appSettingsStore: JammLab.AppSettingsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false },
            applicationSupportDirectory: supportDirectory
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            stemSeparationService: service
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "stems-restart.caf", duration: 1)
        try viewModel.loadImportedAudio(media)

        viewModel.separateStems()
        try await Task.sleep(nanoseconds: 100_000_000)
        let firstRunID = try XCTUnwrap(viewModel.stemSeparationRunID)

        viewModel.cancelStemSeparation()
        viewModel.separateStems()

        XCTAssertEqual(viewModel.stemSeparationRunID, firstRunID)
        XCTAssertNotNil(viewModel.stemSeparationTask)
        XCTAssertEqual(viewModel.stemSeparationState.phase, .processing)
        XCTAssertEqual(viewModel.stemSeparationState.status, "Cancelling stem separation")

        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertNil(viewModel.stemSeparationTask)
        XCTAssertNil(viewModel.stemSeparationRunID)

        viewModel.separateStems()
        try await Task.sleep(nanoseconds: 100_000_000)
        let secondRunID = try XCTUnwrap(viewModel.stemSeparationRunID)
        XCTAssertNotEqual(secondRunID, firstRunID)

        viewModel.cancelStemSeparation()
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(viewModel.stemSeparationState.phase, .cancelled)
        XCTAssertEqual(viewModel.stemSeparationState.status, "Stem separation cancelled")
        XCTAssertNil(viewModel.stemSeparationTask)
        XCTAssertNil(viewModel.stemSeparationRunID)
        XCTAssertTrue(viewModel.stemFiles.isEmpty)
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
