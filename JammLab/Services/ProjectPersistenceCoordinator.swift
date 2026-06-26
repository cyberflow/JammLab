import Foundation

struct ProjectSaveArtifactsInput {
    let importedFile: ImportedAudioFile
    let projectURL: URL
    let peakformData: PeakformData?
    let stemPeakforms: [StemType: PeakformData]
    let stemFiles: [StemFile]
    let stemCacheMetadata: StemCacheMetadata?
}

struct ProjectSaveArtifactsResult {
    var importedFile: ImportedAudioFile?
    var temporaryVideoAudioURLToRemove: URL?
    var peakformURLsToRemove: [URL] = []
    var stemMetadata: StemCacheMetadata?
    var stemCacheKeyToRemove: String?
}

struct ProjectOpenMediaResult {
    let file: ImportedAudioFile
    let projectDuration: TimeInterval
    let shouldAnalyzeTempo: Bool
    let warningMessage: String?
    let resolvedMediaURL: URL?
}

struct ProjectDocumentSnapshot {
    let importedFile: ImportedAudioFile
    let projectURL: URL
    let duration: TimeInterval
    let notes: [TimecodedNote]
    let harmonyEvents: [HarmonyEvent]
    let loopRegion: LoopRegion
    let loopMinimumLength: TimeInterval
    let isLooping: Bool
    let playbackRate: Float
    let pitchShiftSemitones: Float
    let tempoBPM: Double?
    let beatGridSettings: BeatGridSettings
    let mainTrackVolume: Float
    let isClickEnabled: Bool
    let clickVolume: Float
    let isSnapEnabled: Bool
    let playbackMode: PlaybackMode
    let playbackMarkerTime: TimeInterval
    let timelineVisibleRange: ClosedRange<TimeInterval>
    let stemState: StemProjectState?
    let isVideoWindowOpen: Bool
}

struct ProjectPersistenceCoordinator {
    private let projectArtifactStore: ProjectArtifactStore
    private let projectDocumentService: ProjectDocumentService
    private let peakformProvider: PeakformProvider
    private let stemSeparationService: StemSeparationService
    private let fileManager: FileManager
    private let importFileFromURL: (URL) async throws -> ImportedAudioFile
    private let decodedDuration: (URL) throws -> TimeInterval

    init(
        projectArtifactStore: ProjectArtifactStore = ProjectArtifactStore(),
        projectDocumentService: ProjectDocumentService = ProjectDocumentService(),
        importer: AudioFileImporter = AudioFileImporter(),
        peakformProvider: PeakformProvider = CachedPeakformProvider(),
        stemSeparationService: StemSeparationService = StemSeparationService(),
        fileManager: FileManager = .default,
        importFileFromURL: ((URL) async throws -> ImportedAudioFile)? = nil,
        decodedDuration: @escaping (URL) throws -> TimeInterval = AudioFileImporter.decodedDuration(for:)
    ) {
        self.projectArtifactStore = projectArtifactStore
        self.projectDocumentService = projectDocumentService
        self.peakformProvider = peakformProvider
        self.stemSeparationService = stemSeparationService
        self.fileManager = fileManager
        self.importFileFromURL = importFileFromURL ?? { try await importer.importFile(from: $0) }
        self.decodedDuration = decodedDuration
    }

    func prepareSaveArtifacts(_ input: ProjectSaveArtifactsInput) async throws -> ProjectSaveArtifactsResult {
        var file = input.importedFile
        var result = ProjectSaveArtifactsResult()
        try projectArtifactStore.ensureArtifactRoot(for: input.projectURL)
        try projectArtifactStore.ensureArtifactDirectories(for: input.projectURL)
        let previousAudioURL = file.url
        file = try projectArtifactStore.persistVideoAudioIfNeeded(file, projectURL: input.projectURL)
        if file.url != previousAudioURL {
            result.importedFile = file
            result.temporaryVideoAudioURLToRemove = previousAudioURL
        }

        if let peakformData = input.peakformData {
            try projectArtifactStore.writeMainPeakform(peakformData, projectURL: input.projectURL)
            result.peakformURLsToRemove.append(previousAudioURL)
        }

        if !input.stemPeakforms.isEmpty {
            try projectArtifactStore.writeStemPeakforms(input.stemPeakforms, projectURL: input.projectURL)
            result.peakformURLsToRemove.append(contentsOf: input.stemFiles.map(\.url))
        }

        if let metadata = input.stemCacheMetadata {
            let localMetadata = try projectArtifactStore.writeStemMetadata(metadata, projectURL: input.projectURL)
            result.stemMetadata = localMetadata
            result.stemCacheKeyToRemove = localMetadata.cacheKey
        }

        return result
    }

    func finalizeSavedArtifacts(_ result: ProjectSaveArtifactsResult) async {
        if let oldURL = result.temporaryVideoAudioURLToRemove,
           let persistedURL = result.importedFile?.url {
            removeTemporaryVideoAudioIfNeeded(oldURL, persistedURL: persistedURL)
        }

        for url in result.peakformURLsToRemove {
            await peakformProvider.removeCachedPeakform(for: url)
        }

        if let cacheKey = result.stemCacheKeyToRemove {
            stemSeparationService.removeCachedResult(cacheKey: cacheKey)
        }
    }

    func resolveProjectMedia(project: JammLabProject, projectURL: URL) async throws -> ProjectOpenMediaResult {
        let storedProjectTempo = ProjectStateNormalizer.normalizedTempo(project.beatGridSettings?.bpm ?? project.tempoBPM)
        let shouldAnalyzeTempo = storedProjectTempo == nil
        let projectDuration = ProjectStateNormalizer.normalizedDuration(project.audioDuration)
        guard projectDuration > 0 else {
            throw ProjectDocumentError.invalidProjectData("audio duration is missing or zero.")
        }

        let mediaKind = project.mediaKind ?? .audio
        let localVideoAudioURL = projectArtifactStore.existingVideoAudioURL(for: projectURL)
        let resolvedMediaURL: URL?
        let warningMessage: String?

        do {
            resolvedMediaURL = try project.resolvedMediaURL()
            warningMessage = nil
        } catch {
            guard mediaKind == .video, localVideoAudioURL != nil else {
                throw error
            }
            resolvedMediaURL = nil
            warningMessage = "Video source is unavailable; opened saved project audio only."
        }

        let file: ImportedAudioFile
        switch mediaKind {
        case .audio:
            guard let resolvedMediaURL else {
                throw ProjectDocumentError.invalidProjectData("audio file is missing.")
            }
            file = ImportedAudioFile(
                url: resolvedMediaURL,
                displayName: project.audioDisplayName,
                duration: projectDuration
            )
        case .video:
            if let localVideoAudioURL {
                let localDuration = try decodedDuration(localVideoAudioURL)
                file = ImportedAudioFile(
                    url: localVideoAudioURL,
                    sourceMediaURL: resolvedMediaURL ?? localVideoAudioURL,
                    displayName: project.audioDisplayName,
                    duration: localDuration,
                    mediaKind: resolvedMediaURL == nil ? .audio : .video
                )
            } else {
                guard let resolvedMediaURL else {
                    throw ProjectDocumentError.invalidProjectData("video source is missing.")
                }
                let importedVideo = try await importFileFromURL(resolvedMediaURL)
                file = ImportedAudioFile(
                    url: importedVideo.url,
                    sourceMediaURL: resolvedMediaURL,
                    displayName: project.audioDisplayName,
                    duration: importedVideo.duration,
                    mediaKind: .video
                )
            }
        }

        let resolvedProjectDuration = ProjectStateNormalizer.normalizedDuration(file.duration)
        guard resolvedProjectDuration > 0 else {
            throw ProjectDocumentError.invalidProjectData("audio duration is missing or zero.")
        }

        return ProjectOpenMediaResult(
            file: file,
            projectDuration: resolvedProjectDuration,
            shouldAnalyzeTempo: shouldAnalyzeTempo,
            warningMessage: warningMessage,
            resolvedMediaURL: resolvedMediaURL
        )
    }

    func makeProject(_ snapshot: ProjectDocumentSnapshot) throws -> JammLabProject {
        let artifactRootURL = projectArtifactStore.artifactRoot(for: snapshot.projectURL)

        return JammLabProject(
            audioBookmarkData: try projectDocumentService.bookmarkData(for: snapshot.importedFile.sourceMediaURL),
            artifactRootBookmarkData: try? projectDocumentService.bookmarkData(for: artifactRootURL),
            audioDisplayName: snapshot.importedFile.displayName,
            audioDuration: snapshot.duration,
            mediaKind: snapshot.importedFile.mediaKind,
            notes: ProjectStateNormalizer.normalizedNotes(snapshot.notes, duration: snapshot.duration),
            harmonyEvents: ProjectStateNormalizer.normalizedHarmonyEvents(
                snapshot.harmonyEvents,
                tempoMap: TempoMap(
                    baseSettings: snapshot.beatGridSettings,
                    markers: snapshot.notes,
                    duration: snapshot.duration
                )
            ),
            loopStart: snapshot.loopRegion.clamped(to: snapshot.duration, minimumLength: snapshot.loopMinimumLength).start,
            loopEnd: snapshot.loopRegion.clamped(to: snapshot.duration, minimumLength: snapshot.loopMinimumLength).end,
            isLoopEnabled: snapshot.isLooping,
            playbackRate: snapshot.playbackRate,
            pitchShiftSemitones: snapshot.pitchShiftSemitones,
            tempoBPM: snapshot.tempoBPM,
            beatGridSettings: snapshot.beatGridSettings.clamped(to: snapshot.duration),
            mainTrackVolume: snapshot.mainTrackVolume,
            isClickEnabled: snapshot.isClickEnabled,
            clickVolume: snapshot.clickVolume,
            isSnapEnabled: snapshot.isSnapEnabled,
            playbackMode: snapshot.playbackMode,
            playbackMarkerTime: ProjectStateNormalizer.normalizedTimelineTime(snapshot.playbackMarkerTime, duration: snapshot.duration),
            timelineVisibleRange: ProjectTimelineVisibleRange(
                ProjectStateNormalizer.normalizedTimelineVisibleRange(snapshot.timelineVisibleRange, duration: snapshot.duration)
            ),
            stemState: snapshot.stemState,
            isVideoWindowOpen: snapshot.importedFile.mediaKind == .video ? snapshot.isVideoWindowOpen : nil
        )
    }

    private func removeTemporaryVideoAudioIfNeeded(_ oldURL: URL, persistedURL: URL) {
        guard oldURL != persistedURL,
              oldURL.path.contains("/MediaCache/")
        else {
            return
        }

        try? fileManager.removeItem(at: oldURL.deletingLastPathComponent())
    }
}
