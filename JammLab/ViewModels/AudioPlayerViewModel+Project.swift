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

            let candidateMediaLease = try SecurityScopedResourceLease(
                url: file.sourceMediaURL,
                requiresAccess: isSandboxed()
            )
            let preparedAsset = try await prepareOriginalPlayback(for: file, kind: .importing)
            _ = candidateMediaLease
            try loadImportedAudio(file, preparedAsset: preparedAsset)
            finishAudioPreparation()
        } catch {
            isImporting = false
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func importAudio(from url: URL) async {
        errorMessage = nil
        isImporting = true

        do {
            let file = try await importer.importFile(from: url)
            let candidateMediaLease = try SecurityScopedResourceLease(
                url: file.sourceMediaURL,
                requiresAccess: isSandboxed()
            )
            let preparedAsset = try await prepareOriginalPlayback(for: file, kind: .importing)
            _ = candidateMediaLease
            try loadImportedAudio(file, preparedAsset: preparedAsset)
            finishAudioPreparation()
        } catch {
            isImporting = false
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
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
        cancelAudioPreparation()
        stopPlaybackClock()
        playbackEngine.unload()
        performWithoutVideoWindowDirtyTracking {
            videoFollower.unload()
        }
        cancelBackgroundWork()
        clearUndoHistory()

        resetForNewProject()
        applyTempoMapToPlaybackEngine()
        playbackEngine.setClickVolume(clickVolume)
        playbackEngine.setClickEnabled(false)
        endSecurityScopedAccess()
        endProjectSecurityScopedAccess()
        markProjectClean()
    }

    private func resetForNewProject() {
        preparedPlaybackAssets = [:]
        importedFile = nil
        analysisResult = nil
        peakformData = nil
        playbackState = .idle
        currentTime = 0
        playbackMarkerTime = 0
        playbackDisplayState = .idle
        duration = 0
        playbackRate = AppSliderDefaults.playbackRate
        pitchShiftSemitones = AppSliderDefaults.pitchShiftSemitones
        tempoBPM = AppDefaults.defaultTempoBPM
        beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM)
        shouldAcceptAnalyzedTempo = true
        notes = []
        harmonySymbols = []
        notationItems = []
        stemTranscriptionTracks = []
        notationPartClefs = [:]
        stemNotationTrackCollapsed = [:]
        stemNoteDisplayModes = [:]
        visibleNotationPartIDs = [.main]
        projectKeySelection = nil
        clearTransientEditingState()
        loopRegion = .empty
        timelineVisibleRange = 0...0
        userTimelineVisibleRange = 0...0
        currentProjectURL = nil
        isImporting = false
        audioPreparationState = .idle
        isAnalyzing = false
        isBuildingWaveform = false
        resetStemState()
        isLooping = false
        isClickEnabled = false
        isSnapEnabled = false
        isNotationTrackCollapsed = true
        mainTrackVolume = AppSliderDefaults.mainTrackVolume
        clickVolume = AppSliderDefaults.clickVolume
        errorMessage = nil
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
        resetForImportedFile(file)
        clearUndoHistory()

        _ = restoreCachedStems(for: file.url)
        restoreVideoWindowOpenState(file.mediaKind == .video)
        markProjectClean()

        buildPeakform(file: file)
        analyze(file: file, includesTempo: true, includesKey: true)
    }

    func loadImportedAudio(
        _ file: ImportedAudioFile,
        preparedAsset: PreparedPlaybackAsset
    ) throws {
        playbackEngine.stop()
        videoFollower.stop()
        cancelBackgroundWork()

        beginSecurityScopedAccess(for: file.sourceMediaURL)
        do {
            try configurePlayer(with: preparedAsset)
            preparedPlaybackAssets = [.original: preparedAsset]
        } catch {
            endSecurityScopedAccess()
            throw error
        }

        importedFile = file
        performWithoutVideoWindowDirtyTracking {
            videoFollower.load(videoURL: file.videoURL)
        }
        resetForImportedFile(file)
        clearUndoHistory()

        _ = restoreCachedStems(for: file.url)
        restoreVideoWindowOpenState(file.mediaKind == .video)
        markProjectClean()

        buildPeakform(file: file)
        analyze(file: file, includesTempo: true, includesKey: true)
    }

    private func resetForImportedFile(_ file: ImportedAudioFile) {
        currentProjectURL = nil
        duration = file.duration
        currentTime = 0
        playbackMarkerTime = 0
        tempoBPM = AppDefaults.defaultTempoBPM
        beatGridSettings = BeatGridSettings(bpm: AppDefaults.defaultTempoBPM).clamped(to: file.duration)
        shouldAcceptAnalyzedTempo = true
        notes = []
        harmonySymbols = []
        notationItems = []
        stemTranscriptionTracks = []
        notationPartClefs = [:]
        stemNotationTrackCollapsed = [:]
        stemNoteDisplayModes = [:]
        visibleNotationPartIDs = [.main]
        projectKeySelection = nil
        clearTransientEditingState()
        loopRegion = LoopRegion(start: 0, end: file.duration).clamped(to: file.duration)
        timelineVisibleRange = 0...file.duration
        userTimelineVisibleRange = timelineVisibleRange
        playbackState = .stopped
        updatePlaybackDisplayState(sampledTime: 0)
        isNotationTrackCollapsed = true
        resetStemState()
        isImporting = false
    }

    func openProject(at url: URL) async {
        errorMessage = nil
        isImporting = true
        stopPlaybackClock()

        do {
            let candidateProjectLease = try SecurityScopedResourceLease(
                url: url,
                requiresAccess: isSandboxed()
            )
            let project = try projectService.load(from: url)
            var candidateArtifactLease: SecurityScopedResourceLease?
            if let artifactRootURL = try? project.resolvedArtifactRootURL() {
                candidateArtifactLease = try SecurityScopedResourceLease(
                    url: artifactRootURL,
                    requiresAccess: isSandboxed()
                )
            }
            let mediaResult = try await projectPersistenceCoordinator.resolveProjectMedia(project: project, projectURL: url)
            var candidateMediaLease: SecurityScopedResourceLease?
            if let resolvedMediaURL = mediaResult.resolvedMediaURL {
                candidateMediaLease = try SecurityScopedResourceLease(
                    url: resolvedMediaURL,
                    requiresAccess: isSandboxed()
                )
            }
            let projectDuration = mediaResult.projectDuration
            let file = mediaResult.file
            let nextMainTrackVolume = clampedVolume(
                project.mainTrackVolume ?? AppSliderDefaults.mainTrackVolume
            )
            let preparedAsset = try await prepareOriginalPlayback(
                for: file,
                kind: .openingProject,
                volume: nextMainTrackVolume
            )
            _ = candidateProjectLease
            _ = candidateArtifactLease
            _ = candidateMediaLease

            playbackEngine.stop()
            videoFollower.stop()
            playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(project.playbackRate)
            pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(project.pitchShiftSemitones)
            mainTrackVolume = nextMainTrackVolume
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
            synchronizeTempoBPM(beatGridSettings.bpm)
            shouldAcceptAnalyzedTempo = mediaResult.shouldAnalyzeTempo
            isClickEnabled = (project.isClickEnabled ?? false) && beatGridSettings.bpm != nil
            let restoredPlaybackMode = project.playbackMode ?? project.stemState?.playbackMode ?? .original
            let resolvedProjectDuration = mediaResult.projectDuration
            beatGridSettings = beatGridSettings.clamped(to: resolvedProjectDuration)
            synchronizeTempoBPM(tempoBPM)
            try configurePlayer(with: preparedAsset)
            preparedPlaybackAssets = [.original: preparedAsset]

            importedFile = file
            beginSecurityScopedAccess(for: mediaResult.resolvedMediaURL ?? file.sourceMediaURL)
            if let artifactRootURL = try? project.resolvedArtifactRootURL() {
                _ = beginProjectSecurityScopedAccess(for: artifactRootURL)
            } else {
                _ = beginProjectSecurityScopedAccess(for: url)
            }
            performWithoutVideoWindowDirtyTracking {
                videoFollower.load(videoURL: file.videoURL)
            }
            currentProjectURL = url
            duration = resolvedProjectDuration
            let restoredPlaybackMarkerTime = ProjectStateNormalizer.normalizedTimelineTime(
                project.playbackMarkerTime,
                duration: resolvedProjectDuration
            )
            playbackMarkerTime = restoredPlaybackMarkerTime
            currentTime = restoredPlaybackMarkerTime
            notes = ProjectStateNormalizer.normalizedNotes(project.notes, duration: resolvedProjectDuration)
            harmonySymbols = ProjectStateNormalizer.normalizedHarmonySymbols(
                project.harmonySymbols,
                duration: resolvedProjectDuration
            )
            let restoredClefs = restoredNotationPartClefs(from: project)
            notationItems = ProjectStateNormalizer.normalizedNotationItems(
                project.notationItems,
                duration: resolvedProjectDuration,
                notationPartClefs: restoredClefs
            )
            stemTranscriptionTracks = ProjectStateNormalizer.normalizedStemTranscriptionTracks(
                project.stemTranscriptionTracks,
                duration: resolvedProjectDuration,
                notationItems: notationItems
            )
            notationPartClefs = restoredClefs
            sanitizeNotationTieRelationships()
            projectKeySelection = project.projectKeySelection
            clearTransientEditingState()
            loopRegion = ProjectStateNormalizer.normalizedLoopRegion(
                start: project.loopStart,
                end: project.loopEnd,
                duration: resolvedProjectDuration
            )
            isLooping = project.isLoopEnabled ?? false
            applyLoopConfiguration()
            let restoredTimelineVisibleRange = ProjectStateNormalizer.normalizedTimelineVisibleRange(
                project.timelineVisibleRange,
                duration: resolvedProjectDuration
            )
            timelineVisibleRange = restoredTimelineVisibleRange
            userTimelineVisibleRange = restoredTimelineVisibleRange
            playbackState = .stopped
            restoreStemState(project.stemState, audioURL: file.url, projectURL: url)
            restorePlaybackMode(restoredPlaybackMode, preservedTime: currentTime)
            setPlaybackMarkerExactly(to: restoredPlaybackMarkerTime)
            restoreVideoWindowOpenState(file.mediaKind == .video && project.isVideoWindowOpen == true)
            isNotationTrackCollapsed = project.isNotationTrackCollapsed ?? true
            stemNotationTrackCollapsed = project.stemNotationTrackCollapsed
            stemNoteDisplayModes = StemNoteDisplayModes.normalized(project.stemNoteDisplayModes)
            visibleNotationPartIDs = normalizedVisibleNotationPartIDs(from: project.visibleNotationPartIDs)
            isImporting = false
            finishAudioPreparation()
            clearUndoHistory()
            markProjectClean()
            if let warningMessage = mediaResult.warningMessage {
                errorMessage = warningMessage
            }

            addRecentProject(url: url)
            buildPeakform(file: file)
            let shouldAnalyzeKey = project.projectKeySelection == nil
            analyze(
                file: file,
                includesTempo: shouldAcceptAnalyzedTempo,
                includesKey: shouldAnalyzeKey,
                marksProjectModifiedForAutoKey: shouldAnalyzeKey
            )
        } catch {
            isImporting = false
            if error is CancellationError {
                return
            }
            errorMessage = "Project open failed: \(error.localizedDescription)"
        }
    }

    private func restoredNotationPartClefs(from project: JammLabProject) -> [NotationPartID: Clef] {
        NotationPartClefOverrides.restored(
            project.notationPartClefs,
            projectFormatVersion: project.formatVersion,
            hasLegacyDrumNotationEvidence: hasLegacyDrumNotationEvidence(project),
            legacyBassPartIDs: legacyBassPartIDs(project)
        )
    }

    private func hasLegacyDrumNotationEvidence(_ project: JammLabProject) -> Bool {
        let drumPartID = NotationPartID.stem(.drums)
        return project.notationItems.contains { $0.partID == drumPartID }
            || project.stemState?.mixState.item(for: .drums).isAvailable == true
            || project.visibleNotationPartIDs.contains(drumPartID)
            || project.stemNotationTrackCollapsed[.drums] != nil
            || project.stemNoteDisplayModes[.drums] != nil
    }

    private func legacyBassPartIDs(_ project: JammLabProject) -> Set<NotationPartID> {
        var partIDs = Set(project.notationItems.compactMap { item in
            item.partID.stemType == .bass ? item.partID : nil
        })
        partIDs.formUnion(project.visibleNotationPartIDs.filter { $0.stemType == .bass })

        for acceptedTrack in ProjectStateNormalizer.acceptedStemTranscriptionTracks(
            project.stemTranscriptionTracks
        ) where acceptedTrack.track.stemType == .bass {
            partIDs.insert(acceptedTrack.partID)
        }

        if project.stemState?.mixState.item(for: .bass).isAvailable == true
            || project.stemNotationTrackCollapsed[.bass] != nil
            || project.stemNoteDisplayModes[.bass] != nil {
            partIDs.insert(.stem(.bass))
        }
        return partIDs
    }

    private func clearTransientEditingState() {
        selectedRegionID = nil
        selectedHarmonySymbolID = nil
        clearNotationMeasureSelectionAndClipboard()
        pendingHarmonyEditorRequest = nil
        notationDurationDenominator = NotationDuration.defaultDenominator
        notationEntryDurationIsDotted = false
        selectedDrumInstrumentMIDINoteNumber = DrumInstrumentMap.defaultMIDINoteNumber
        notationEntryMode = nil
        clearPendingNotationAccidental()
        activeLoopRegionID = nil
    }

    func cancelBackgroundWork() {
        analysisTask?.cancel()
        analysisTask = nil
        waveformTask?.cancel()
        waveformTask = nil
        stemSeparationTask?.cancel()
        stemSeparationTask = nil
        stemSeparationRunID = nil
        stemPeakformTask?.cancel()
        stemPeakformTask = nil
        for operation in stemTranscriptionOperations.values {
            operation.cancel()
        }
        for task in stemTranscriptionTasks.values {
            task.cancel()
        }
        stemTranscriptionOperations = [:]
        stemTranscriptionTasks = [:]
        stemTranscriptionRunIDs = [:]
        stemTranscriptionStates = [:]
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
                let snapshot = projectDocumentSnapshot(
                    importedFile: self.importedFile ?? currentImportedFile,
                    projectURL: url
                )
                let project = try projectPersistenceCoordinator.makeProject(snapshot)
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

    private func projectDocumentSnapshot(importedFile: ImportedAudioFile, projectURL: URL) -> ProjectDocumentSnapshot {
        ProjectDocumentSnapshot(
            importedFile: importedFile,
            projectURL: projectURL,
            duration: duration,
            notes: notes,
            harmonySymbols: harmonySymbols,
            notationItems: notationItems,
            stemTranscriptionTracks: stemTranscriptionTracks,
            notationPartClefs: NotationPartClefOverrides.normalized(notationPartClefs),
            projectKeySelection: projectKeySelection,
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
            playbackMarkerTime: playbackMarkerTime,
            timelineVisibleRange: userTimelineVisibleRange,
            stemState: makeStemProjectState(),
            isVideoWindowOpen: isVideoWindowOpen,
            isNotationTrackCollapsed: isNotationTrackCollapsed,
            stemNotationTrackCollapsed: stemNotationTrackCollapsed,
            stemNoteDisplayModes: StemNoteDisplayModes.normalized(stemNoteDisplayModes),
            visibleNotationPartIDs: normalizedVisibleNotationPartIDs()
        )
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

}
