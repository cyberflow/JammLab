import XCTest
@testable import JammLab

final class ViewModelStemSeparationCancellationTests: XCTestCase {
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
}
