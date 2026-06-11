import Foundation

extension AudioPlayerViewModel {
    func importAudio() async {
        errorMessage = nil
        isImporting = true

        do {
            guard let file = try await importer.importFile() else {
                isImporting = false
                return
            }

            try loadImportedAudio(file)
        } catch {
            isImporting = false
            errorMessage = error.localizedDescription
        }
    }

    func importAudio(from url: URL) async {
        errorMessage = nil
        isImporting = true

        do {
            let file = try await importer.importFile(from: url)
            try loadImportedAudio(file)
        } catch {
            isImporting = false
            errorMessage = error.localizedDescription
        }
    }

    func openProject() async {
        guard let url = projectService.chooseProjectToOpen() else { return }
        await openProject(at: url)
    }

    func openRecentProject(_ entry: RecentProjectEntry) async {
        do {
            let url = try entry.resolvedURL()
            guard recentProjectsStore.canOpenProject(at: url) else {
                recentProjectsStore.remove(entry)
                errorMessage = "Could not open recent project: The file doesn’t exist."
                return
            }
            await openProject(at: url)
        } catch {
            errorMessage = "Could not open recent project: \(error.localizedDescription)"
            recentProjectsStore.remove(entry)
        }
    }

    @discardableResult
    func saveProject() async -> Bool {
        if let currentProjectURL {
            return await saveProject(to: currentProjectURL)
        } else {
            return await saveProjectAs()
        }
    }

    @discardableResult
    func saveProjectAs() async -> Bool {
        let defaultName = defaultProjectFilename()
        guard let destination = projectService.chooseProjectSaveDestination(defaultName: defaultName) else { return false }
        guard beginProjectSecurityScopedAccess(for: destination.securityScopedAccessURL) || !isSandboxed() else {
            let error: ProjectDocumentError = destination.createSubdirectory
                ? .projectArtifactAccessDenied
                : .projectArtifactAccessDeniedUseProjectFolder
            errorMessage = "Project save failed: \(error.localizedDescription)"
            return false
        }
        return await saveProject(to: destination.projectURL)
    }

    @discardableResult
    func saveProjectForClose() async -> Bool {
        guard importedFile != nil else { return false }
        return await saveProject()
    }

    func newProject() {
        playbackEngine.unload()
        videoFollower.unload()
        cancelBackgroundWork()
        clearUndoHistory()

        importedFile = nil
        analysisResult = nil
        peakformData = nil
        playbackState = .idle
        currentTime = 0
        duration = 0
        playbackRate = AppSliderDefaults.playbackRate
        pitchShiftSemitones = AppSliderDefaults.pitchShiftSemitones
        tempoBPM = AppDefaults.defaultTempoBPM
        beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        shouldAcceptAnalyzedTempo = true
        notes = []
        selectedRegionID = nil
        activeLoopRegionID = nil
        loopRegion = .empty
        timelineVisibleRange = 0...0
        currentProjectURL = nil
        isImporting = false
        isAnalyzing = false
        isBuildingWaveform = false
        resetStemState()
        isLooping = false
        isClickEnabled = false
        isSnapEnabled = false
        mainTrackVolume = AppSliderDefaults.mainTrackVolume
        clickVolume = AppSliderDefaults.clickVolume
        errorMessage = nil
        playbackEngine.setClickSettings(beatGridSettings)
        playbackEngine.setClickVolume(clickVolume)
        playbackEngine.setClickEnabled(false)
        endSecurityScopedAccess()
        endProjectSecurityScopedAccess()
        markProjectClean()
    }

    func loadImportedAudio(_ file: ImportedAudioFile) throws {
        playbackEngine.stop()
        videoFollower.stop()
        cancelBackgroundWork()

        beginSecurityScopedAccess(for: file.sourceMediaURL)
        do {
            try configurePlayer(with: file)
        } catch {
            endSecurityScopedAccess()
            throw error
        }

        importedFile = file
        videoFollower.load(videoURL: file.videoURL)
        currentProjectURL = nil
        duration = file.duration
        currentTime = 0
        tempoBPM = AppDefaults.defaultTempoBPM
        beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM).clamped(to: file.duration)
        shouldAcceptAnalyzedTempo = true
        notes = []
        selectedRegionID = nil
        activeLoopRegionID = nil
        loopRegion = LoopRegion(start: 0, end: file.duration).clamped(to: file.duration)
        timelineVisibleRange = 0...file.duration
        playbackState = .stopped
        resetStemState()
        isImporting = false
        clearUndoHistory()

        _ = restoreCachedStems(for: file.url)
        markProjectClean()

        buildPeakform(file: file)
        analyze(file: file)
    }

    func openProject(at url: URL) async {
        errorMessage = nil
        isImporting = true
        var didAdoptProject = false

        do {
            beginProjectSecurityScopedAccess(for: url)
            let project = try projectService.load(from: url)
            if let artifactRootURL = try? project.resolvedArtifactRootURL() {
                beginProjectSecurityScopedAccess(for: artifactRootURL)
            }
            let projectDuration = ProjectStateNormalizer.normalizedDuration(project.audioDuration)
            guard projectDuration > 0 else {
                throw ProjectDocumentError.invalidProjectData("audio duration is missing or zero.")
            }

            let mediaKind = project.mediaKind ?? .audio
            let localVideoAudioURL = projectArtifactStore.existingVideoAudioURL(for: url)
            let mediaURL: URL?
            let mediaWarning: String?
            do {
                let resolvedMediaURL = try project.resolvedMediaURL()
                beginSecurityScopedAccess(for: resolvedMediaURL)
                mediaURL = resolvedMediaURL
                mediaWarning = nil
            } catch {
                guard mediaKind == .video, localVideoAudioURL != nil else {
                    throw error
                }
                mediaURL = nil
                mediaWarning = "Video source is unavailable; opened saved project audio only."
            }

            playbackEngine.stop()
            videoFollower.stop()
            playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(project.playbackRate)
            pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(project.pitchShiftSemitones)
            mainTrackVolume = clampedVolume(project.mainTrackVolume ?? AppSliderDefaults.mainTrackVolume)
            clickVolume = clampedVolume(project.clickVolume ?? AppSliderDefaults.clickVolume)
            isSnapEnabled = project.isSnapEnabled ?? false
            let storedProjectTempo = ProjectStateNormalizer.normalizedTempo(project.beatGridSettings?.bpm ?? project.tempoBPM)
            let shouldAnalyzeTempo = storedProjectTempo == nil
            beatGridSettings = ProjectStateNormalizer.normalizedBeatGridSettings(
                projectSettings: project.beatGridSettings,
                legacyTempoBPM: project.tempoBPM,
                duration: projectDuration
            )
            if beatGridSettings.bpm == nil {
                beatGridSettings.bpm = AppDefaults.defaultTempoBPM
            }
            tempoBPM = beatGridSettings.bpm
            beatGridSettings.bpm = tempoBPM
            shouldAcceptAnalyzedTempo = shouldAnalyzeTempo
            isClickEnabled = (project.isClickEnabled ?? false) && beatGridSettings.bpm != nil
            let restoredPlaybackMode = project.playbackMode ?? project.stemState?.playbackMode ?? .original
            let file: ImportedAudioFile
            switch mediaKind {
            case .audio:
                guard let mediaURL else {
                    throw ProjectDocumentError.invalidProjectData("audio file is missing.")
                }
                file = ImportedAudioFile(
                    url: mediaURL,
                    displayName: project.audioDisplayName,
                    duration: projectDuration
                )
            case .video:
                if let localVideoAudioURL,
                   let localDuration = try? AudioFileImporter.decodedDuration(for: localVideoAudioURL) {
                    file = ImportedAudioFile(
                        url: localVideoAudioURL,
                        sourceMediaURL: mediaURL ?? localVideoAudioURL,
                        displayName: project.audioDisplayName,
                        duration: localDuration,
                        mediaKind: mediaURL == nil ? .audio : .video
                    )
                } else {
                    guard let mediaURL else {
                        throw ProjectDocumentError.invalidProjectData("video source is missing.")
                    }
                    let importedVideo = try await importer.importFile(from: mediaURL)
                    file = ImportedAudioFile(
                        url: importedVideo.url,
                        sourceMediaURL: mediaURL,
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
            beatGridSettings = beatGridSettings.clamped(to: resolvedProjectDuration)
            beatGridSettings.bpm = tempoBPM
            try configurePlayer(with: file)

            importedFile = file
            videoFollower.load(videoURL: file.videoURL)
            currentProjectURL = url
            didAdoptProject = true
            duration = resolvedProjectDuration
            currentTime = 0
            notes = ProjectStateNormalizer.normalizedNotes(project.notes, duration: resolvedProjectDuration)
            selectedRegionID = nil
            activeLoopRegionID = nil
            loopRegion = ProjectStateNormalizer.normalizedLoopRegion(
                start: project.loopStart,
                end: project.loopEnd,
                duration: resolvedProjectDuration
            )
            isLooping = project.isLoopEnabled ?? false
            applyLoopConfiguration()
            timelineVisibleRange = 0...resolvedProjectDuration
            playbackState = .stopped
            restoreStemState(project.stemState, audioURL: file.url, projectURL: url)
            restorePlaybackMode(restoredPlaybackMode, preservedTime: currentTime)
            isImporting = false
            clearUndoHistory()
            markProjectClean()
            if let mediaWarning {
                errorMessage = mediaWarning
            }

            addRecentProject(url: url)
            buildPeakform(file: file)
            analyze(file: file, includesTempo: shouldAcceptAnalyzedTempo)
        } catch {
            isImporting = false
            if !didAdoptProject {
                endSecurityScopedAccess()
                endProjectSecurityScopedAccess()
            }
            errorMessage = "Project open failed: \(error.localizedDescription)"
        }
    }

    func cancelBackgroundWork() {
        analysisTask?.cancel()
        analysisTask = nil
        waveformTask?.cancel()
        waveformTask = nil
        stemSeparationTask?.cancel()
        stemSeparationTask = nil
        stemPeakformTask?.cancel()
        stemPeakformTask = nil
        stemSeparationService.cancel()
    }

    func saveProject(to url: URL) async -> Bool {
        errorMessage = nil

        do {
            guard ensureProjectArtifactAccess(for: url) else {
                throw ProjectDocumentError.projectArtifactAccessDenied
            }
            let persistenceResult = try await prepareProjectArtifacts(to: url)
            let previousImportedFile = importedFile

            if let persistedFile = persistenceResult.importedFile {
                importedFile = persistedFile
            }

            do {
                let project = try makeProject(projectURL: url)
                try projectService.save(project, to: url)
            } catch {
                importedFile = previousImportedFile
                throw error
            }

            currentProjectURL = url
            await applyProjectArtifactPersistence(persistenceResult)
            addRecentProject(url: url)
            markProjectClean()
            return true
        } catch {
            errorMessage = "Project save failed: \(error.localizedDescription)"
            return false
        }
    }

    struct ProjectArtifactPersistenceResult {
        var importedFile: ImportedAudioFile?
        var temporaryVideoAudioURLToRemove: URL?
        var peakformURLsToRemove: [URL] = []
        var stemMetadata: StemCacheMetadata?
        var stemCacheKeyToRemove: String?
    }

    func prepareProjectArtifacts(to projectURL: URL) async throws -> ProjectArtifactPersistenceResult {
        guard var file = importedFile else {
            throw ProjectDocumentError.missingAudioFile
        }

        var result = ProjectArtifactPersistenceResult()
        try projectArtifactStore.ensureArtifactRoot(for: projectURL)
        try projectArtifactStore.ensureArtifactDirectories(for: projectURL)
        let previousAudioURL = file.url
        file = try projectArtifactStore.persistVideoAudioIfNeeded(file, projectURL: projectURL)
        if file.url != previousAudioURL {
            result.importedFile = file
            result.temporaryVideoAudioURLToRemove = previousAudioURL
        }

        if let peakformData {
            try projectArtifactStore.writeMainPeakform(peakformData, projectURL: projectURL)
            result.peakformURLsToRemove.append(previousAudioURL)
        }

        if !stemPeakforms.isEmpty {
            try projectArtifactStore.writeStemPeakforms(stemPeakforms, projectURL: projectURL)
            result.peakformURLsToRemove.append(contentsOf: stemFiles.map(\.url))
        }

        if let metadata = stemCacheMetadata {
            let localMetadata = try projectArtifactStore.writeStemMetadata(metadata, projectURL: projectURL)
            result.stemMetadata = localMetadata
            result.stemCacheKeyToRemove = localMetadata.cacheKey
        }

        return result
    }

    func applyProjectArtifactPersistence(_ result: ProjectArtifactPersistenceResult) async {
        if let oldURL = result.temporaryVideoAudioURLToRemove,
           let persistedURL = result.importedFile?.url {
            removeTemporaryVideoAudioIfNeeded(oldURL, persistedURL: persistedURL)
        }

        for url in result.peakformURLsToRemove {
            await peakformProvider.removeCachedPeakform(for: url)
        }

        if let metadata = result.stemMetadata {
            stemCacheMetadata = metadata
            stemFiles = metadata.stems
            stemMixState.setAvailability(from: metadata.stems)
        }

        if let cacheKey = result.stemCacheKeyToRemove {
            stemSeparationService.removeCachedResult(cacheKey: cacheKey)
        }
    }

    func makeProject(projectURL: URL) throws -> JammLabProject {
        guard let importedFile else {
            throw ProjectDocumentError.missingAudioFile
        }
        let artifactRootURL = projectArtifactStore.artifactRoot(for: projectURL)

        return JammLabProject(
            audioBookmarkData: try projectService.bookmarkData(for: importedFile.sourceMediaURL),
            artifactRootBookmarkData: try? projectService.bookmarkData(for: artifactRootURL),
            audioDisplayName: importedFile.displayName,
            audioDuration: duration,
            mediaKind: importedFile.mediaKind,
            notes: ProjectStateNormalizer.normalizedNotes(notes, duration: duration),
            loopStart: loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength).start,
            loopEnd: loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength).end,
            isLoopEnabled: isLooping,
            playbackRate: playbackRate,
            pitchShiftSemitones: pitchShiftSemitones,
            tempoBPM: tempoBPM,
            beatGridSettings: beatGridSettings.clamped(to: duration),
            mainTrackVolume: mainTrackVolume,
            isClickEnabled: isClickEnabled,
            clickVolume: clickVolume,
            isSnapEnabled: isSnapEnabled,
            playbackMode: playbackMode,
            stemState: makeStemProjectState()
        )
    }

    func defaultProjectFilename() -> String {
        let baseName = (importedFile?.displayName as NSString?)?.deletingPathExtension ?? "JammLab Project"

        return "\(baseName).\(ProjectDocumentService.fileExtension)"
    }

    func addRecentProject(url: URL) {
        guard let bookmarkData = try? projectService.bookmarkData(for: url) else { return }
        recentProjectsStore.addProject(url: url, bookmarkData: bookmarkData)
    }

    func beginSecurityScopedAccess(for url: URL) {
        endSecurityScopedAccess()
        hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        securityScopedURL = hasSecurityScopedAccess ? url : nil
    }

    func endSecurityScopedAccess() {
        if hasSecurityScopedAccess {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }

        securityScopedURL = nil
        hasSecurityScopedAccess = false
    }

    @discardableResult
    func beginProjectSecurityScopedAccess(for url: URL) -> Bool {
        endProjectSecurityScopedAccess()
        hasProjectSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        projectSecurityScopedURL = hasProjectSecurityScopedAccess ? url : nil
        return hasProjectSecurityScopedAccess
    }

    func endProjectSecurityScopedAccess() {
        if hasProjectSecurityScopedAccess {
            projectSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }

        projectSecurityScopedURL = nil
        hasProjectSecurityScopedAccess = false
    }

    func ensureProjectArtifactAccess(for projectURL: URL) -> Bool {
        guard isSandboxed() else { return true }

        let artifactRootURL = projectArtifactStore.artifactRoot(for: projectURL).standardizedFileURL
        if hasProjectSecurityScopedAccess,
           projectSecurityScopedURL?.standardizedFileURL == artifactRootURL {
            return true
        }

        return beginProjectSecurityScopedAccess(for: artifactRootURL)
    }

    func analyze(file: ImportedAudioFile, includesTempo: Bool = true) {
        analysisTask?.cancel()
        isAnalyzing = true
        analysisResult = nil

        analysisTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await analyzer.analyze(url: file.url, includesTempo: includesTempo)
                guard !Task.isCancelled else { return }
                analysisResult = result
                if includesTempo, shouldAcceptAnalyzedTempo, let analyzedBPM = result.bpm {
                    tempoBPM = Double(analyzedBPM)
                    beatGridSettings.bpm = tempoBPM
                    beatGridSettings.automaticFirstBeatTime = 0
                    beatGridSettings.firstBeatTime = 0
                    beatGridSettings.alignmentSource = .automatic
                    beatGridSettings.lastChangedAt = Date()
                    playbackEngine.setClickSettings(beatGridSettings)
                    playbackEngine.setClickEnabled(isClickEnabled && beatGridSettings.bpm != nil)
                    if !isProjectModified {
                        markProjectClean()
                    } else {
                        refreshProjectModifiedState()
                    }
                }
                isAnalyzing = false
            } catch {
                guard !Task.isCancelled else { return }
                isAnalyzing = false
                errorMessage = "Analysis failed: \(error.localizedDescription)"
            }
        }
    }

    func persistStemArtifactsIfNeeded(_ metadata: StemCacheMetadata) throws -> StemCacheMetadata {
        guard let currentProjectURL else { return metadata }
        let localMetadata = try projectArtifactStore.writeStemMetadata(metadata, projectURL: currentProjectURL)
        stemSeparationService.removeCachedResult(cacheKey: metadata.cacheKey)
        return localMetadata
    }

    func removeTemporaryVideoAudioIfNeeded(_ oldURL: URL, persistedURL: URL) {
        guard oldURL != persistedURL,
              oldURL.path.contains("/MediaCache/")
        else {
            return
        }

        try? FileManager.default.removeItem(at: oldURL.deletingLastPathComponent())
    }

    func buildPeakform(file: ImportedAudioFile) {
        waveformTask?.cancel()
        isBuildingWaveform = true
        peakformData = nil

        if let currentProjectURL,
           let projectPeakform = try? projectArtifactStore.readMainPeakform(projectURL: currentProjectURL) {
            peakformData = projectPeakform
            isBuildingWaveform = false
            return
        }

        waveformTask = Task { [weak self] in
            guard let self else { return }

            do {
                let peakform = try await peakformProvider.peakform(for: file.url)
                guard !Task.isCancelled else { return }
                peakformData = peakform
                isBuildingWaveform = false
                if let currentProjectURL {
                    try? projectArtifactStore.writeMainPeakform(peakform, projectURL: currentProjectURL)
                    await peakformProvider.removeCachedPeakform(for: file.url)
                }
            } catch {
                guard !Task.isCancelled else { return }
                isBuildingWaveform = false
                errorMessage = "Peakform failed: \(error.localizedDescription)"
            }
        }
    }
}
