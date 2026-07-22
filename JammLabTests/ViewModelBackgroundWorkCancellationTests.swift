import XCTest
@testable import JammLab

final class ViewModelBackgroundWorkCancellationTests: XCTestCase {
    @MainActor
    func testStaleAnalysisSuccessDoesNotReplaceNewerResult() async throws {
        let analyzer = ControlledAnalyzer()
        let viewModel = AudioPlayerViewModel(
            analyzer: analyzer,
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        let firstFile = importedFile(named: "first.wav")
        let secondFile = importedFile(named: "second.wav")
        let firstResult = AnalysisResult(bpm: 90, keyName: "C major", keyConfidence: 0.8)
        let secondResult = AnalysisResult(bpm: 132, keyName: "G major", keyConfidence: 0.9)

        viewModel.analyze(file: firstFile)
        let firstTask = try XCTUnwrap(viewModel.analysisTask)
        let firstRequest = await analyzer.nextRequest()
        viewModel.analyze(file: secondFile)
        let secondTask = try XCTUnwrap(viewModel.analysisTask)
        let secondRequest = await analyzer.nextRequest()

        await analyzer.succeed(secondRequest, with: secondResult)
        await secondTask.value

        await analyzer.succeed(firstRequest, with: firstResult)
        await firstTask.value

        XCTAssertEqual(viewModel.analysisResult, secondResult)
        XCTAssertEqual(viewModel.tempoBPM, Double(secondResult.bpm ?? 0))
        XCTAssertEqual(viewModel.projectKeySelection?.canonicalKeyName, secondResult.keyName)
        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testStaleAnalysisFailureDoesNotPublishAfterNewProject() async throws {
        let analyzer = ControlledAnalyzer()
        let viewModel = AudioPlayerViewModel(
            analyzer: analyzer,
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )

        viewModel.analyze(file: importedFile(named: "cancelled.wav"))
        let task = try XCTUnwrap(viewModel.analysisTask)
        let request = await analyzer.nextRequest()
        viewModel.newProject()

        await analyzer.fail(request, with: ControlledBackgroundWorkError.expectedFailure)
        await task.value

        XCTAssertNil(viewModel.analysisResult)
        XCTAssertNil(viewModel.projectKeySelection)
        XCTAssertEqual(viewModel.tempoBPM, AppDefaults.defaultTempoBPM)
        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testStalePeakformSuccessDoesNotPublishOrWriteIntoNewProject() async throws {
        let provider = ControlledPeakformProvider()
        let artifactStore = ProjectArtifactStore()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: provider,
            playbackEngine: MockPlaybackEngine(),
            projectArtifactStore: artifactStore
        )
        let directory = temporaryDirectory()
        let firstProjectURL = directory.appendingPathComponent("first.jammlab")
        let secondProjectURL = directory.appendingPathComponent("second.jammlab")
        defer { try? FileManager.default.removeItem(at: directory) }
        let peakform = PeakformData(
            duration: 2,
            sampleRate: 44_100,
            levels: [PeakformLevel(samplesPerPeak: 512, peaks: [PeakPoint(min: -0.5, max: 0.5, rms: 0.25)])]
        )

        viewModel.currentProjectURL = firstProjectURL
        viewModel.buildPeakform(file: importedFile(named: "first.wav"))
        let task = try XCTUnwrap(viewModel.waveformTask)
        let request = await provider.nextRequest()
        viewModel.newProject()
        viewModel.currentProjectURL = secondProjectURL

        await provider.succeed(request, with: peakform)
        await task.value

        XCTAssertNil(viewModel.peakformData)
        XCTAssertFalse(viewModel.isBuildingWaveform)
        XCTAssertNil(try artifactStore.readMainPeakform(projectURL: secondProjectURL))
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testStalePeakformFailureDoesNotPublishAfterNewProject() async throws {
        let provider = ControlledPeakformProvider()
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: provider,
            playbackEngine: MockPlaybackEngine()
        )

        viewModel.buildPeakform(file: importedFile(named: "cancelled.wav"))
        let task = try XCTUnwrap(viewModel.waveformTask)
        let request = await provider.nextRequest()
        viewModel.newProject()

        await provider.fail(request, with: ControlledBackgroundWorkError.expectedFailure)
        await task.value

        XCTAssertNil(viewModel.peakformData)
        XCTAssertFalse(viewModel.isBuildingWaveform)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func importedFile(named name: String) -> ImportedAudioFile {
        ImportedAudioFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            duration: 2
        )
    }

}

private enum ControlledBackgroundWorkError: Error {
    case expectedFailure
}

private final class ControlledAnalyzer: AudioAnalyzing {
    private let requests = ControlledRequestQueue<AnalysisResult>()

    func analyze(url: URL, includesTempo: Bool, includesKey: Bool) async throws -> AnalysisResult {
        try await requests.suspend()
    }

    func nextRequest() async -> Int {
        await requests.nextRequest()
    }

    func succeed(_ request: Int, with result: AnalysisResult) async {
        await requests.succeed(request, with: result)
    }

    func fail(_ request: Int, with error: Error) async {
        await requests.fail(request, with: error)
    }

}

private final class ControlledPeakformProvider: PeakformProvider {
    let samplesPerPeakLevels = PeakformData.defaultSamplesPerPeakLevels
    private let requests = ControlledRequestQueue<PeakformData>()

    func peakform(for url: URL) async throws -> PeakformData {
        try await requests.suspend()
    }

    func nextRequest() async -> Int {
        await requests.nextRequest()
    }

    func succeed(_ request: Int, with peakform: PeakformData) async {
        await requests.succeed(request, with: peakform)
    }

    func fail(_ request: Int, with error: Error) async {
        await requests.fail(request, with: error)
    }

}

private actor ControlledRequestQueue<Output> {
    private var nextRequestID = 0
    private var pendingRequestIDs: [Int] = []
    private var requestWaiters: [CheckedContinuation<Int, Never>] = []
    private var continuations: [Int: CheckedContinuation<Output, Error>] = [:]
    func suspend() async throws -> Output {
        let requestID = nextRequestID
        nextRequestID += 1
        announce(requestID)

        return try await withCheckedThrowingContinuation { continuation in
            continuations[requestID] = continuation
        }
    }

    func nextRequest() async -> Int {
        if !pendingRequestIDs.isEmpty {
            return pendingRequestIDs.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func succeed(_ requestID: Int, with output: Output) {
        continuations.removeValue(forKey: requestID)?.resume(returning: output)
    }

    func fail(_ requestID: Int, with error: Error) {
        continuations.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    private func announce(_ requestID: Int) {
        if !requestWaiters.isEmpty {
            requestWaiters.removeFirst().resume(returning: requestID)
        } else {
            pendingRequestIDs.append(requestID)
        }
    }
}
