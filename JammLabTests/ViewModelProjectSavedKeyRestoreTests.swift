import XCTest
@testable import JammLab

final class ViewModelProjectSavedKeyRestoreTests: XCTestCase {
    @MainActor
    private func waitForAnalysisToFinish(_ viewModel: AudioPlayerViewModel) async {
        for _ in 0..<50 {
            if !viewModel.isAnalyzing { return }
            await Task.yield()
        }
    }

    @MainActor
    func testProjectOpenWithSavedKeySkipsKeyDetection() async throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        let projectURL = temporaryDirectory().appendingPathComponent("saved-key-open.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let savedKey = ProjectKeySelection(
            tonic: .aSharpBb,
            mode: .major,
            source: .user,
            confidence: nil
        )
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 4,
            notes: [],
            projectKeySelection: savedKey,
            loopStart: 0,
            loopEnd: 4,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        let analyzer = MockAnalyzer()
        analyzer.result = AnalysisResult(bpm: 90, keyName: "D minor", keyConfidence: 0.9)
        let viewModel = AudioPlayerViewModel(
            analyzer: analyzer,
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openProject(at: projectURL)
        await waitForAnalysisToFinish(viewModel)

        XCTAssertTrue(analyzer.calls.isEmpty)
        XCTAssertEqual(viewModel.projectKeySelection, savedKey)
        XCTAssertEqual(viewModel.effectiveKeyName, "Bb major")
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testProjectOpenWithSavedKeyAndMissingTempoRunsTempoOnlyAnalysis() async throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        let projectURL = temporaryDirectory().appendingPathComponent("saved-key-missing-tempo.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let savedKey = ProjectKeySelection(
            tonic: .gSharpAb,
            mode: .minor,
            source: .user,
            confidence: nil
        )
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 4,
            notes: [],
            projectKeySelection: savedKey,
            loopStart: 0,
            loopEnd: 4,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones
        )
        try projectService.save(project, to: projectURL)
        let analyzer = MockAnalyzer()
        analyzer.result = AnalysisResult(bpm: 96, keyName: "D major", keyConfidence: 0.9)
        let viewModel = AudioPlayerViewModel(
            analyzer: analyzer,
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        await viewModel.openProject(at: projectURL)
        await waitForAnalysisToFinish(viewModel)

        XCTAssertEqual(analyzer.calls.count, 1)
        XCTAssertEqual(analyzer.calls.first?.includesTempo, true)
        XCTAssertEqual(analyzer.calls.first?.includesKey, false)
        XCTAssertEqual(viewModel.projectKeySelection, savedKey)
        XCTAssertEqual(viewModel.effectiveKeyName, "G# minor")
        XCTAssertEqual(try XCTUnwrap(viewModel.tempoBPM), 96, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(viewModel.beatGridSettings.bpm), 96, accuracy: 0.0001)
        XCTAssertFalse(viewModel.isProjectModified)
    }
}
