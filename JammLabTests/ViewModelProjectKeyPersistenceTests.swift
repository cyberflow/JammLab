import XCTest
@testable import JammLab

final class ViewModelProjectKeyPersistenceTests: XCTestCase {
    @MainActor
    private func waitForAnalysisToFinish(_ viewModel: AudioPlayerViewModel) async {
        for _ in 0..<50 {
            if !viewModel.isAnalyzing { return }
            await Task.yield()
        }
    }

    @MainActor
    func testImportAutoDetectsProjectKeyAndPersistsOnSave() async throws {
        let audioURL = try temporaryAudioFile(duration: 2)
        let projectURL = temporaryDirectory().appendingPathComponent("auto-key-save.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let analyzer = MockAnalyzer()
        analyzer.result = AnalysisResult(bpm: 120, keyName: "F# minor", keyConfidence: 0.82)
        let projectService = ProjectDocumentService()
        let viewModel = AudioPlayerViewModel(
            analyzer: analyzer,
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults()),
            isSandboxed: { false }
        )

        try viewModel.loadImportedAudio(ImportedAudioFile(url: audioURL, displayName: "auto-key.wav", duration: 2))
        await waitForAnalysisToFinish(viewModel)

        XCTAssertEqual(analyzer.calls.map(\.includesTempo), [true])
        XCTAssertEqual(analyzer.calls.map(\.includesKey), [true])
        XCTAssertEqual(viewModel.projectKeySelection?.tonic, .fSharpGb)
        XCTAssertEqual(viewModel.projectKeySelection?.mode, .minor)
        XCTAssertEqual(viewModel.projectKeySelection?.source, .auto)
        XCTAssertFalse(viewModel.isProjectModified)

        let didSave = await viewModel.saveProject(to: projectURL)

        XCTAssertTrue(didSave)
        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(savedProject.projectKeySelection?.canonicalKeyName, "F# minor")
        XCTAssertEqual(savedProject.projectKeySelection?.source, .auto)
    }

    @MainActor
    func testProjectOpenWithoutSavedKeyRunsKeyDetectionAndMarksDirtyForPersistence() async throws {
        let audioURL = try temporaryAudioFile(duration: 4)
        let projectURL = temporaryDirectory().appendingPathComponent("legacy-auto-key-open.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 4,
            notes: [],
            loopStart: 0,
            loopEnd: 4,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        let analyzer = MockAnalyzer()
        analyzer.result = AnalysisResult(bpm: 140, keyName: "Bb major", keyConfidence: 0.74)
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
        XCTAssertEqual(analyzer.calls.first?.includesTempo, false)
        XCTAssertEqual(analyzer.calls.first?.includesKey, true)
        XCTAssertEqual(viewModel.projectKeySelection?.tonic, .aSharpBb)
        XCTAssertEqual(viewModel.projectKeySelection?.mode, .major)
        XCTAssertEqual(viewModel.projectKeySelection?.source, .auto)
        XCTAssertTrue(viewModel.isProjectModified)

        let didSave = await viewModel.saveProjectForClose()

        XCTAssertTrue(didSave)
        let savedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(savedProject.projectKeySelection?.canonicalKeyName, "Bb major")
    }
}
