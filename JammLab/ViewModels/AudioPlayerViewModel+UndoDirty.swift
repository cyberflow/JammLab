import Foundation

extension AudioPlayerViewModel {
    var editableState: ProjectEditableState {
        ProjectEditableState(
            notes: notes,
            selectedRegionID: selectedRegionID,
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
            isVideoWindowOpen: importedFile?.mediaKind == .video && isVideoWindowOpen
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
        tempoBPM = ProjectStateNormalizer.normalizedTempo(state.tempoBPM)
        beatGridSettings = state.beatGridSettings.clamped(to: duration)
        beatGridSettings.bpm = tempoBPM
        shouldAcceptAnalyzedTempo = false
        notes = ProjectStateNormalizer.normalizedNotes(state.notes, duration: duration)
        selectedRegionID = availableRegionID(state.selectedRegionID)
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

    func clampedVolume(_ volume: Float) -> Float {
        guard volume.isFinite else { return AppSliderDefaults.mainTrackVolume }
        return min(1, max(0, volume))
    }
}
