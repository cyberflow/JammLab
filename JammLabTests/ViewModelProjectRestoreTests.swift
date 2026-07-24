import XCTest
@testable import JammLab

final class ViewModelProjectRestoreTests: XCTestCase {
    @MainActor
    func testProjectOpenRestoresLoopClickAndSnapButtonStates() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("toggles.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 2,
            notes: [],
            loopStart: 0.25,
            loopEnd: 1.25,
            isLoopEnabled: true,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM),
            mainTrackVolume: AppSliderDefaults.mainTrackVolume,
            isClickEnabled: true,
            clickVolume: 0.33,
            isSnapEnabled: true
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "toggles",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertTrue(viewModel.isLooping)
        XCTAssertTrue(viewModel.isClickEnabled)
        XCTAssertTrue(viewModel.isSnapEnabled)
        XCTAssertEqual(viewModel.clickVolume, 0.33, accuracy: 0.0001)
        XCTAssertTrue(engine.loopEnabled)
        XCTAssertEqual(engine.loopRegion.start, 0.25, accuracy: 0.0001)
        XCTAssertEqual(engine.loopRegion.end, 1.25, accuracy: 0.0001)
        XCTAssertTrue(engine.clickEnabled)
    }

    @MainActor
    func testLegacyProjectOpenDefaultsLoopClickAndSnapToOff() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("legacy-toggles.jammlab")
        try FileManager.default.createDirectory(at: projectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            formatVersion: 4,
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 0.5,
            notes: [],
            loopStart: 0.1,
            loopEnd: 0.4,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: AppDefaults.defaultTempoBPM,
            beatGridSettings: BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "legacy-toggles",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let engine = MockPlaybackEngine()
        let viewModel = AudioPlayerViewModel(
            playbackEngine: engine,
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertFalse(viewModel.isLooping)
        XCTAssertFalse(viewModel.isClickEnabled)
        XCTAssertFalse(viewModel.isSnapEnabled)
        XCTAssertEqual(viewModel.playbackMarkerTime, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentTime, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timelineVisibleRange.upperBound, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.userTimelineVisibleRange.upperBound, 0.5, accuracy: 0.0001)
        XCTAssertFalse(engine.loopEnabled)
        XCTAssertFalse(engine.clickEnabled)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testLegacyProjectRestoresTreblePerBassPartAndNormalizesMismatchedTranscriptionID() async throws {
        let audioURL = try temporaryAudioFile()
        let projectURL = temporaryDirectory().appendingPathComponent("legacy-bass-clefs.jammlab")
        try FileManager.default.createDirectory(
            at: projectURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let legacyPart = NotationPartID.stemTranscription(
            .bass,
            trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000721")!
        )
        let explicitBassPart = NotationPartID.stemTranscription(
            .bass,
            trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000722")!
        )
        let validTrack = StemTranscriptionTrack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000731")!,
            stemType: .bass,
            notationPartID: legacyPart,
            sourceFingerprint: StemSourceFingerprint(path: "/legacy/bass-1.wav", fileSize: 1, modificationTime: 1),
            configuration: .neuralNoteDefaults,
            notes: []
        )
        let explicitBassTrack = StemTranscriptionTrack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000732")!,
            stemType: .bass,
            notationPartID: explicitBassPart,
            sourceFingerprint: StemSourceFingerprint(path: "/legacy/bass-2.wav", fileSize: 1, modificationTime: 1),
            configuration: .neuralNoteDefaults,
            notes: []
        )
        let mismatchedTrack = StemTranscriptionTrack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000733")!,
            stemType: .bass,
            notationPartID: .main,
            sourceFingerprint: StemSourceFingerprint(path: "/legacy/bass-3.wav", fileSize: 1, modificationTime: 1),
            configuration: .neuralNoteDefaults,
            notes: []
        )
        let invalidPart = NotationPartID.stemTranscription(
            .bass,
            trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000723")!
        )
        let invalidTrack = StemTranscriptionTrack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000734")!,
            stemType: .bass,
            notationPartID: invalidPart,
            sourceFingerprint: StemSourceFingerprint(path: "", fileSize: 1, modificationTime: 1),
            configuration: .neuralNoteDefaults,
            notes: []
        )
        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            formatVersion: 15,
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 0.5,
            notes: [],
            stemTranscriptionTracks: [validTrack, explicitBassTrack, mismatchedTrack, invalidTrack],
            notationPartClefs: [explicitBassPart: .bass],
            loopStart: 0,
            loopEnd: 0.5,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "legacy-bass-clefs",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertEqual(viewModel.notationClef(for: legacyPart), .treble)
        XCTAssertEqual(viewModel.notationClef(for: explicitBassPart), .bass)
        XCTAssertEqual(viewModel.notationClef(for: .stem(.bass)), .treble)
        XCTAssertEqual(viewModel.notationPartClefs[legacyPart], .treble)
        XCTAssertEqual(viewModel.notationPartClefs[explicitBassPart], .bass)
        XCTAssertEqual(viewModel.notationPartClefs[.stem(.bass)], .treble)
        XCTAssertEqual(viewModel.notationClef(for: invalidPart), .bass8)
        XCTAssertNil(viewModel.notationPartClefs[invalidPart])
        XCTAssertEqual(
            viewModel.stemTranscriptionTracks.first { $0.id == mismatchedTrack.id }?.notationPartID,
            .stem(.bass)
        )
        XCTAssertFalse(viewModel.stemTranscriptionTracks.contains { $0.id == invalidTrack.id })
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testLegacyBassNotationClefsPersistAcrossFormatUpgradeAndReopen() async throws {
        let audioURL = try temporaryAudioFile(duration: 2)
        let projectURL = temporaryDirectory().appendingPathComponent("legacy-bass-notation.jammlab")
        try FileManager.default.createDirectory(
            at: projectURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let canonicalPart = NotationPartID.stem(.bass)
        let transcriptionPart = NotationPartID.stemTranscription(
            .bass,
            trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000724")!
        )
        let canonicalPitch = NotationPitch(step: .e, octave: 4)
        let transcriptionPitch = NotationPitch(step: .g, octave: 4)
        let notationItems = [
            NotationMeasureItem(
                id: "legacy-canonical-bass-note",
                partID: canonicalPart,
                kind: .note,
                pitch: canonicalPitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "legacy-transcription-bass-note",
                partID: transcriptionPart,
                kind: .note,
                pitch: transcriptionPitch,
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            formatVersion: 15,
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            artifactRootBookmarkData: try projectService.bookmarkData(
                for: projectURL.deletingLastPathComponent()
            ),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 2,
            notes: [],
            notationItems: notationItems,
            loopStart: 0,
            loopEnd: 2,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: 120,
            beatGridSettings: BeatGridSettings(bpm: 120)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "legacy-bass-notation",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertEqual(viewModel.notationClef(for: canonicalPart), .treble)
        XCTAssertEqual(viewModel.notationClef(for: transcriptionPart), .treble)
        XCTAssertEqual(
            viewModel.notationItems.first { $0.id == "legacy-canonical-bass-note" }?.pitch,
            canonicalPitch
        )
        XCTAssertEqual(
            viewModel.notationItems.first { $0.id == "legacy-transcription-bass-note" }?.pitch,
            transcriptionPitch
        )
        let didSave = await viewModel.saveProject()
        XCTAssertTrue(didSave, viewModel.errorMessage ?? "Project save returned false without an error")

        let upgradedProject = try projectService.load(from: projectURL)
        XCTAssertEqual(upgradedProject.formatVersion, JammLabProject.currentFormatVersion)
        XCTAssertEqual(upgradedProject.notationPartClefs, [
            canonicalPart: .treble,
            transcriptionPart: .treble
        ])

        let reopenedViewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )
        await reopenedViewModel.openRecentProject(entry)

        XCTAssertEqual(reopenedViewModel.notationClef(for: canonicalPart), .treble)
        XCTAssertEqual(reopenedViewModel.notationClef(for: transcriptionPart), .treble)
        XCTAssertEqual(
            reopenedViewModel.notationItems.first { $0.id == "legacy-canonical-bass-note" }?.pitch,
            canonicalPitch
        )
        XCTAssertEqual(
            reopenedViewModel.notationItems.first { $0.id == "legacy-transcription-bass-note" }?.pitch,
            transcriptionPitch
        )
    }

    @MainActor
    func testCurrentBassNotationEvidenceUsesBass8Default() async throws {
        let audioURL = try temporaryAudioFile(duration: 2)
        let projectURL = temporaryDirectory().appendingPathComponent("current-bass-notation.jammlab")
        try FileManager.default.createDirectory(
            at: projectURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let canonicalPart = NotationPartID.stem(.bass)
        let transcriptionPart = NotationPartID.stemTranscription(
            .bass,
            trackID: UUID(uuidString: "00000000-0000-0000-0000-000000000725")!
        )
        let notationItems = [
            NotationMeasureItem(
                id: "current-canonical-bass-note",
                partID: canonicalPart,
                kind: .note,
                pitch: NotationPitch(step: .e, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            ),
            NotationMeasureItem(
                id: "current-transcription-bass-note",
                partID: transcriptionPart,
                kind: .note,
                pitch: NotationPitch(step: .g, octave: 2),
                measureNumber: 1,
                measureStartTime: 0,
                offsetInQuarterNotes: 0,
                durationInQuarterNotes: 1,
                displayDuration: NotationDuration(denominator: 4)
            )
        ]
        let projectService = ProjectDocumentService()
        let project = JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: audioURL),
            audioDisplayName: audioURL.lastPathComponent,
            audioDuration: 2,
            notes: [],
            notationItems: notationItems,
            loopStart: 0,
            loopEnd: 2,
            playbackRate: AppSliderDefaults.playbackRate,
            pitchShiftSemitones: AppSliderDefaults.pitchShiftSemitones,
            tempoBPM: 120,
            beatGridSettings: BeatGridSettings(bpm: 120)
        )
        try projectService.save(project, to: projectURL)
        let entry = RecentProjectEntry(
            displayName: "current-bass-notation",
            bookmarkData: try projectService.bookmarkData(for: projectURL)
        )
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: RecentProjectsStore(defaults: try temporaryUserDefaults())
        )

        await viewModel.openRecentProject(entry)

        XCTAssertEqual(viewModel.notationClef(for: canonicalPart), .bass8)
        XCTAssertEqual(viewModel.notationClef(for: transcriptionPart), .bass8)
        XCTAssertTrue(viewModel.notationPartClefs.isEmpty)
        XCTAssertEqual(
            viewModel.notationItems.first { $0.id == "current-canonical-bass-note" }?.pitch,
            NotationPitch(step: .e, octave: 2)
        )
        XCTAssertEqual(
            viewModel.notationItems.first { $0.id == "current-transcription-bass-note" }?.pitch,
            NotationPitch(step: .g, octave: 2)
        )
    }

    @MainActor
    func testOpenRecentProjectRemovesMissingProjectEntry() async throws {
        let defaults = try temporaryUserDefaults()
        let projectURL = try temporaryFile(name: "missing-recent.jammlab", contents: "{}")
        let projectDirectory = projectURL.deletingLastPathComponent()
        let projectService = ProjectDocumentService()
        let store = RecentProjectsStore(defaults: defaults)
        store.addProject(url: projectURL, bookmarkData: try projectService.bookmarkData(for: projectURL))
        let entry = try XCTUnwrap(store.entries.first)
        try FileManager.default.removeItem(at: projectDirectory)
        let viewModel = AudioPlayerViewModel(
            playbackEngine: MockPlaybackEngine(),
            projectService: projectService,
            recentProjectsStore: store
        )

        await viewModel.openRecentProject(entry)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Could not open recent project: The file doesn’t exist.")
    }
}
