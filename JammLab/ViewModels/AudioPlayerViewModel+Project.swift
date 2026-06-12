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
        performWithoutVideoWindowDirtyTracking {
            videoFollower.unload()
        }
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
        performWithoutVideoWindowDirtyTracking {
            videoFollower.load(videoURL: file.videoURL)
        }
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
        restoreVideoWindowOpenState(file.mediaKind == .video)
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
            let mediaResult = try await projectPersistenceCoordinator.resolveProjectMedia(project: project, projectURL: url)
            if let resolvedMediaURL = mediaResult.resolvedMediaURL {
                beginSecurityScopedAccess(for: resolvedMediaURL)
            }
            let projectDuration = mediaResult.projectDuration

            playbackEngine.stop()
            videoFollower.stop()
            playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(project.playbackRate)
            pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(project.pitchShiftSemitones)
            mainTrackVolume = clampedVolume(project.mainTrackVolume ?? AppSliderDefaults.mainTrackVolume)
            clickVolume = clampedVolume(project.clickVolume ?? AppSliderDefaults.clickVolume)
            isSnapEnabled = project.isSnapEnabled ?? false
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
            shouldAcceptAnalyzedTempo = mediaResult.shouldAnalyzeTempo
            isClickEnabled = (project.isClickEnabled ?? false) && beatGridSettings.bpm != nil
            let restoredPlaybackMode = project.playbackMode ?? project.stemState?.playbackMode ?? .original
            let file = mediaResult.file
            let resolvedProjectDuration = mediaResult.projectDuration
            beatGridSettings = beatGridSettings.clamped(to: resolvedProjectDuration)
            beatGridSettings.bpm = tempoBPM
            try configurePlayer(with: file)

            importedFile = file
            performWithoutVideoWindowDirtyTracking {
                videoFollower.load(videoURL: file.videoURL)
            }
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
            restoreVideoWindowOpenState(file.mediaKind == .video && project.isVideoWindowOpen == true)
            isImporting = false
            clearUndoHistory()
            markProjectClean()
            if let warningMessage = mediaResult.warningMessage {
                errorMessage = warningMessage
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
            guard let currentImportedFile = importedFile else {
                throw ProjectDocumentError.missingAudioFile
            }
            let persistenceResult = try await projectPersistenceCoordinator.prepareSaveArtifacts(ProjectSaveArtifactsInput(
                importedFile: currentImportedFile,
                projectURL: url,
                peakformData: peakformData,
                stemPeakforms: stemPeakforms,
                stemFiles: stemFiles,
                stemCacheMetadata: stemCacheMetadata
            ))
            let previousImportedFile = currentImportedFile

            if let persistedFile = persistenceResult.importedFile {
                importedFile = persistedFile
            }

            do {
                let project = try projectPersistenceCoordinator.makeProject(ProjectDocumentSnapshot(
                    importedFile: self.importedFile ?? currentImportedFile,
                    projectURL: url,
                    duration: duration,
                    notes: notes,
                    loopRegion: loopRegion,
                    loopMinimumLength: activeRangeMinimumLength,
                    isLooping: isLooping,
                    playbackRate: playbackRate,
                    pitchShiftSemitones: pitchShiftSemitones,
                    tempoBPM: tempoBPM,
                    beatGridSettings: beatGridSettings,
                    mainTrackVolume: mainTrackVolume,
                    isClickEnabled: isClickEnabled,
                    clickVolume: clickVolume,
                    isSnapEnabled: isSnapEnabled,
                    playbackMode: playbackMode,
                    stemState: makeStemProjectState(),
                    isVideoWindowOpen: isVideoWindowOpen
                ))
                try projectService.save(project, to: url)
            } catch {
                importedFile = previousImportedFile
                throw error
            }

            currentProjectURL = url
            await projectPersistenceCoordinator.finalizeSavedArtifacts(persistenceResult)
            if let metadata = persistenceResult.stemMetadata {
                stemCacheMetadata = metadata
                stemFiles = metadata.stems
                stemMixState.setAvailability(from: metadata.stems)
            }
            addRecentProject(url: url)
            markProjectClean()
            return true
        } catch {
            errorMessage = "Project save failed: \(error.localizedDescription)"
            return false
        }
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
