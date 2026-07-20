import Foundation

extension AudioPlayerViewModel {
    var editableState: ProjectEditableState {
        ProjectEditableState(
            notes: notes,
            harmonySymbols: harmonySymbols,
            notationItems: notationItems,
            notationPartClefs: NotationPartClefOverrides.normalized(notationPartClefs),
            visibleNotationPartIDs: normalizedVisibleNotationPartIDs(),
            projectKeySelection: projectKeySelection,
            selectedRegionID: selectedRegionID,
            selectedHarmonySymbolID: selectedHarmonySymbolID,
            activeLoopRegionID: activeLoopRegionID,
            loopRegion: loopRegion,
            isLooping: isLooping,
            tempoBPM: tempoBPM,
            beatGridSettings: beatGridSettings,
            playbackRate: playbackRate,
            pitchShiftSemitones: pitchShiftSemitones,
            mainTrackVolume: mainTrackVolume,
            stemMixState: stemMixState,
            playbackMode: playbackMode,
            isClickEnabled: isClickEnabled,
            clickVolume: clickVolume,
            isSnapEnabled: isSnapEnabled
        )
    }

    var persistedEditableState: ProjectPersistedEditableState? {
        guard importedFile != nil else { return nil }

        let clampedLoop = loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength)

        return ProjectPersistedEditableState(
            notes: ProjectStateNormalizer.normalizedNotes(notes, duration: duration),
            harmonySymbols: ProjectStateNormalizer.normalizedHarmonySymbols(harmonySymbols, duration: duration),
            notationItems: ProjectStateNormalizer.normalizedNotationItems(notationItems, duration: duration),
            notationPartClefs: NotationPartClefOverrides.normalized(notationPartClefs),
            stemNotationTrackCollapsed: stemNotationTrackCollapsed,
            stemNoteDisplayModes: StemNoteDisplayModes.normalized(stemNoteDisplayModes),
            visibleNotationPartIDs: normalizedVisibleNotationPartIDs(),
            projectKeySelection: projectKeySelection,
            loopRegion: clampedLoop,
            isLooping: isLooping,
            tempoBPM: ProjectStateNormalizer.normalizedTempo(tempoBPM),
            beatGridSettings: beatGridSettings.clamped(to: duration),
            playbackRate: ProjectStateNormalizer.normalizedPlaybackRate(playbackRate),
            pitchShiftSemitones: ProjectStateNormalizer.normalizedPitchShift(pitchShiftSemitones),
            mainTrackVolume: clampedVolume(mainTrackVolume),
            stemMixState: stemMixState,
            playbackMode: playbackMode,
            isClickEnabled: isClickEnabled,
            clickVolume: clampedVolume(clickVolume),
            isSnapEnabled: isSnapEnabled,
            playbackMarkerTime: ProjectStateNormalizer.normalizedTimelineTime(playbackMarkerTime, duration: duration),
            timelineVisibleRange: ProjectStateNormalizer.normalizedTimelineVisibleRange(userTimelineVisibleRange, duration: duration),
            isVideoWindowOpen: importedFile?.mediaKind == .video && isVideoWindowOpen,
            isNotationTrackCollapsed: isNotationTrackCollapsed
        )
    }

    func restoreEditableState(_ state: ProjectEditableState) {
        let wasRestoringUndoState = isRestoringUndoState
        isRestoringUndoState = true
        defer {
            isRestoringUndoState = wasRestoringUndoState
            refreshUndoAvailability()
        }

        let preservedTime = currentTime

        playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(state.playbackRate)
        pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(state.pitchShiftSemitones)
        mainTrackVolume = clampedVolume(state.mainTrackVolume)
        clickVolume = clampedVolume(state.clickVolume)
        isSnapEnabled = state.isSnapEnabled
        isLooping = state.isLooping
        beatGridSettings = state.beatGridSettings.clamped(to: duration)
        synchronizeTempoBPM(state.tempoBPM)
        shouldAcceptAnalyzedTempo = false
        notes = ProjectStateNormalizer.normalizedNotes(state.notes, duration: duration)
        harmonySymbols = ProjectStateNormalizer.normalizedHarmonySymbols(state.harmonySymbols, duration: duration)
        notationItems = ProjectStateNormalizer.normalizedNotationItems(state.notationItems, duration: duration)
        notationPartClefs = NotationPartClefOverrides.normalized(state.notationPartClefs)
        sanitizeNotationTieRelationships()
        visibleNotationPartIDs = normalizedVisibleNotationPartIDs(from: state.visibleNotationPartIDs)
        projectKeySelection = state.projectKeySelection
        selectedRegionID = availableRegionID(state.selectedRegionID)
        selectedHarmonySymbolID = availableHarmonySymbolID(state.selectedHarmonySymbolID)
        selectedNotationItem = nil
        activeLoopRegionID = availableRegionID(state.activeLoopRegionID)
        loopRegion = state.loopRegion.clamped(to: duration, minimumLength: activeRangeMinimumLength)
        stemMixState = state.stemMixState
        stemMixState.setAvailability(from: stemFiles)
        isClickEnabled = state.isClickEnabled && canPlay && beatGridSettings.bpm != nil

        restorePlaybackMode(state.playbackMode, preservedTime: preservedTime)
        playbackEngine.applyMix(stemMixState)
        applyLoopConfiguration()
        applyPlaybackConfiguration()

        if canPlay {
            activePlaybackEngine.seek(to: preservedTime)
        }
        currentTime = preservedTime
        refreshProjectModifiedState()
    }

    func undoLastEdit() {
        undoManager?.undo()
        refreshUndoAvailability()
    }

    func redoLastEdit() {
        undoManager?.redo()
        refreshUndoAvailability()
    }

    func performUndoableEdit(_ actionName: String, edit: () -> Void) {
        let previousState = editableState
        edit()

        if editableState != previousState {
            registerUndoState(previousState, actionName: actionName)
        }
        refreshProjectModifiedState()
    }

    func setProjectKeySelection(_ selection: ProjectKeySelection) {
        performUndoableEdit("Change Key") {
            projectKeySelection = selection.asUserSelection
        }
    }

    func setNotationTrackCollapsed(_ isCollapsed: Bool) {
        guard isNotationTrackCollapsed != isCollapsed else { return }
        isNotationTrackCollapsed = isCollapsed
        refreshProjectModifiedState()
    }

    func setStemNotationTrackCollapsed(_ stemType: StemType, isCollapsed: Bool) {
        guard stemNotationTrackCollapsed[stemType] != isCollapsed else { return }
        stemNotationTrackCollapsed[stemType] = isCollapsed
        refreshProjectModifiedState()
    }

    func registerUndoState(_ state: ProjectEditableState, actionName: String) {
        guard !isRestoringUndoState, let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { target in
            let redoState = target.editableState
            target.restoreEditableState(state)
            target.registerUndoState(redoState, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        refreshUndoAvailability()
    }

    func clearUndoHistory() {
        undoManager?.removeAllActions(withTarget: self)
        refreshUndoAvailability()
    }

    func refreshUndoAvailability() {
        undoStateRevision += 1
    }

    func markProjectClean() {
        lastSavedProjectState = persistedEditableState
        refreshProjectModifiedState()
    }

    func refreshProjectModifiedState() {
        isProjectModified = persistedEditableState != lastSavedProjectState
    }

    func availableRegionID(_ id: TimecodedNote.ID?) -> TimecodedNote.ID? {
        guard let id, notes.contains(where: { $0.id == id && $0.isRegion }) else { return nil }
        return id
    }

    func availableHarmonySymbolID(_ id: HarmonySymbol.ID?) -> HarmonySymbol.ID? {
        guard let id, harmonySymbols.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func clampedVolume(_ volume: Float) -> Float {
        guard volume.isFinite else { return AppSliderDefaults.mainTrackVolume }
        return min(1, max(0, volume))
    }
}
