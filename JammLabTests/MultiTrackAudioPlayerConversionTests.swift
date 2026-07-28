import AVFoundation
import XCTest
@testable import JammLab

final class MultiTrackAudioPlayerConversionTests: XCTestCase {
    func testBackgroundPreparerDecodesOriginalAndReportsCompletion() async throws {
        let url = try temporaryAudioFile(duration: 0.1, namePrefix: "prepared")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let completed = expectation(description: "Preparation completed")

        let asset = try await MultiTrackAudioPreparer().prepareOriginal(
            url: url,
            volume: 0.75
        ) { progress in
            if progress.fractionCompleted == 1 {
                completed.fulfill()
            }
        }
        await fulfillment(of: [completed], timeout: 2)

        guard case .decoded(let format, let tracks) = asset.storage else {
            return XCTFail("Expected decoded playback asset")
        }
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertNil(tracks[0].stemType)
        XCTAssertEqual(tracks[0].volume, 0.75)
        XCTAssertGreaterThan(tracks[0].buffer.frameLength, 0)
    }

    func testPreparationMemoryPolicyRejectsOversizedCandidate() {
        let policy = AudioPreparationMemoryPolicy(maximumCandidateBytes: 1_024)

        XCTAssertThrowsError(
            try policy.validate(frameCount: 10_000, channelCount: 2)
        ) { error in
            guard case MultiTrackAudioPlayerError.preparationMemoryLimitExceeded = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMatchingFormatDecodeChecksCancellationBetweenChunks() throws {
        let url = try temporaryAudioFile(duration: 2, namePrefix: "cancelled-decode")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = try AVAudioFile(forReading: url)
        let outputFormat = file.processingFormat
        var cancellationChecks = 0

        XCTAssertThrowsError(
            try AudioFileBufferDecoder.decode(
                file: file,
                to: outputFormat,
                cancellationCheck: {
                    cancellationChecks += 1
                    if cancellationChecks == 3 {
                        throw CancellationError()
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(cancellationChecks, 3)
        XCTAssertLessThan(file.framePosition, file.length)
    }

    func testCancellingPreparationPropagatesToDetachedDecodeWorker() async throws {
        let url = try temporaryAudioFile(duration: 2, namePrefix: "cancelled-preparation")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let task = Task {
            try await MultiTrackAudioPreparer().prepareOriginal(
                url: url,
                volume: 1
            ) { _ in }
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testDecodeConvertsIntegerPCMWithoutTruncatingSamples() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("integer-pcm.caf")
        try writeIntegerPCMFile(to: url, duration: 0.5)

        let file = try AVAudioFile(forReading: url)
        let outputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        ))
        let buffer = try AudioFileBufferDecoder.decode(file: file, to: outputFormat)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])

        XCTAssertEqual(buffer.frameLength, AVAudioFrameCount(44_100 * 0.5))
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(samples[$0]) > 0.01 })
    }

    private func writeIntegerPCMFile(to url: URL, duration: TimeInterval) throws {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ))
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount

        let samples = try XCTUnwrap(buffer.int16ChannelData?[0])
        for frame in 0..<Int(frameCount) {
            samples[frame] = Int16(sin(Double(frame) * 0.05) * 8_000)
        }

        try file.write(from: buffer)
    }
}

final class AudioPlaybackTransactionTests: XCTestCase {
    @MainActor
    func testImportedAudioInstallFailureRestoresPreviousPlayback() throws {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        let oldFile = ImportedAudioFile(
            url: URL(fileURLWithPath: "/tmp/old.wav"),
            displayName: "old.wav",
            duration: 30
        )
        let newFile = ImportedAudioFile(
            url: URL(fileURLWithPath: "/tmp/new.wav"),
            displayName: "new.wav",
            duration: 45
        )
        try viewModel.loadImportedAudio(oldFile)
        viewModel.preparedPlaybackAssets[.original] = PreparedPlaybackAsset(storage: .originalURL(oldFile.url))
        viewModel.currentTime = 12
        viewModel.playbackState = .playing
        engine.currentTime = 12
        engine.isPlaying = true
        engine.queuedLoadErrors = [TestPlaybackTransactionError.installFailed]

        XCTAssertThrowsError(
            try viewModel.loadImportedAudio(
                newFile,
                preparedAsset: PreparedPlaybackAsset(storage: .originalURL(newFile.url))
            )
        )

        XCTAssertEqual(viewModel.importedFile, oldFile)
        XCTAssertEqual(viewModel.playbackState, .playing)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 12, accuracy: 0.0001)
    }

    @MainActor
    func testImportedAudioInstallAndRecoveryFailureCannotRemainGhostPlaying() throws {
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine)
        let oldFile = ImportedAudioFile(
            url: URL(fileURLWithPath: "/tmp/old.wav"),
            displayName: "old.wav",
            duration: 30
        )
        let newFile = ImportedAudioFile(
            url: URL(fileURLWithPath: "/tmp/new.wav"),
            displayName: "new.wav",
            duration: 45
        )
        try viewModel.loadImportedAudio(oldFile)
        viewModel.preparedPlaybackAssets[.original] = PreparedPlaybackAsset(storage: .originalURL(oldFile.url))
        viewModel.playbackState = .playing
        engine.isPlaying = true
        engine.queuedLoadErrors = [
            TestPlaybackTransactionError.installFailed,
            TestPlaybackTransactionError.recoveryFailed
        ]

        XCTAssertThrowsError(
            try viewModel.loadImportedAudio(
                newFile,
                preparedAsset: PreparedPlaybackAsset(storage: .originalURL(newFile.url))
            )
        ) { error in
            XCTAssertTrue(error is AudioPlaybackTransactionFailure)
        }

        XCTAssertEqual(viewModel.importedFile, oldFile)
        XCTAssertEqual(viewModel.playbackState, .paused)
        XCTAssertFalse(engine.isLoaded)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(viewModel.clockTask)
    }
}

private enum TestPlaybackTransactionError: LocalizedError {
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
