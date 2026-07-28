import Foundation

extension AudioPlayerViewModel {
    func prepareOriginalPlayback(
        for file: ImportedAudioFile,
        kind: AudioPreparationKind,
        volume: Float? = nil
    ) async throws -> PreparedPlaybackAsset {
        audioPreparationTask?.cancel()
        let runID = UUID()
        audioPreparationRunID = runID
        audioPreparationState = AudioPreparationViewState(
            kind: kind,
            phase: .decoding,
            progress: 0,
            status: "Preparing audio",
            pendingPlaybackMode: .original,
            isCancellable: true
        )

        let preparer = playbackPreparer
        let volume = volume ?? mainTrackVolume
        let task = Task {
            try await preparer.prepareOriginal(url: file.url, volume: volume) { [weak self] progress in
                Task { @MainActor in
                    guard self?.audioPreparationRunID == runID else { return }
                    self?.audioPreparationState = AudioPreparationViewState(
                        kind: kind,
                        phase: .decoding,
                        progress: progress.fractionCompleted,
                        status: progress.status,
                        pendingPlaybackMode: .original,
                        isCancellable: true
                    )
                }
            }
        }
        audioPreparationTask = task

        do {
            let asset = try await task.value
            try Task.checkCancellation()
            guard audioPreparationRunID == runID else { throw CancellationError() }
            audioPreparationState = AudioPreparationViewState(
                kind: kind,
                phase: .installing,
                progress: 1,
                status: "Installing audio",
                pendingPlaybackMode: .original,
                isCancellable: false
            )
            return asset
        } catch {
            if audioPreparationRunID == runID {
                audioPreparationTask = nil
                audioPreparationRunID = nil
                audioPreparationState = AudioPreparationViewState(
                    kind: kind,
                    phase: error is CancellationError ? .cancelled : .failed,
                    progress: nil,
                    status: error is CancellationError ? "Audio preparation cancelled" : error.localizedDescription,
                    pendingPlaybackMode: nil,
                    isCancellable: false
                )
            }
            throw error
        }
    }

    func finishAudioPreparation() {
        audioPreparationTask = nil
        audioPreparationRunID = nil
        audioPreparationState = .idle
    }

    func cancelAudioPreparation() {
        guard audioPreparationState.isCancellable else { return }
        audioPreparationTask?.cancel()
        audioPreparationState.phase = .cancelled
        audioPreparationState.progress = nil
        audioPreparationState.status = "Cancelling audio preparation"
        audioPreparationState.isCancellable = false
    }

    var clickVolumeText: String {
        "\(Int((clickVolume * 100).rounded()))%"
    }

    func play() {
        guard canPlay else { return }

        do {
            seekExactly(to: playbackMarkerTime)
            try activePlaybackEngine.play()
            videoFollower.play(rate: playbackRate)
            playbackState = .playing
            updatePlaybackDisplayState(sampledTime: currentTime)
            startPlaybackClock()
        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard canPlay else { return }
        stopPlaybackClock()
        activePlaybackEngine.pause()
        videoFollower.pause()
        let targetTime = ProjectStateNormalizer.normalizedTimelineTime(activePlaybackEngine.currentTime, duration: duration)
        playbackMarkerTime = targetTime
        currentTime = targetTime
        playbackState = .paused
        updatePlaybackDisplayState(sampledTime: targetTime)
        refreshProjectModifiedState()
    }

    func stop() {
        guard canPlay else { return }
        stopPlaybackClock()
        activePlaybackEngine.stop()
        videoFollower.stop()
        seekExactly(to: playbackMarkerTime)
        showPlaybackMarkerInTimeline()
        playbackState = .stopped
        updatePlaybackDisplayState(sampledTime: currentTime)
    }

    func togglePlayStop() {
        guard canPlay else { return }

        if playbackState == .playing {
            stop()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        guard canPlay else { return }
        let targetTime = snappedTimelineTime(time)
        activePlaybackEngine.seek(to: targetTime)
        videoFollower.seek(to: targetTime)
        currentTime = targetTime
        updatePlaybackDisplayState(sampledTime: targetTime)
    }

    func locatePlaybackMarker(to time: TimeInterval) {
        guard canPlay else { return }
        let targetTime = snappedTimelineTime(time)
        playbackMarkerTime = targetTime
        activePlaybackEngine.seek(to: targetTime)
        videoFollower.seek(to: targetTime)
        currentTime = targetTime
        updatePlaybackDisplayState(sampledTime: targetTime)
        refreshProjectModifiedState()
    }

    func locatePlaybackMarkerExactly(to time: TimeInterval) {
        setPlaybackMarkerExactly(to: time)
        refreshProjectModifiedState()
    }

    func seekToStart() {
        setPlaybackMarkerExactly(to: 0)
        refreshProjectModifiedState()
    }

    func seekToEnd() {
        guard canPlay else { return }

        if playbackState == .playing {
            activePlaybackEngine.pause()
            playbackState = .paused
        }

        setPlaybackMarkerExactly(to: duration)
        refreshProjectModifiedState()
    }

    func setLooping(_ isEnabled: Bool) {
        performUndoableEdit("Toggle Loop") {
            isLooping = isEnabled
            applyLoopConfiguration()
            updatePlaybackDisplayState()
        }
    }

    func setPlaybackRate(_ rate: Float) {
        performUndoableEdit("Change Speed") {
            playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(rate)
            playbackEngine.setPlaybackRate(playbackRate)
            videoFollower.setPlaybackRate(playbackRate)
            updatePlaybackDisplayState()
        }
    }

    func resetPlaybackRateToDefault() {
        setPlaybackRate(AppSliderDefaults.playbackRate)
    }

    func setPitchShift(semitones: Float) {
        performUndoableEdit("Change Pitch") {
            pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(semitones)
            playbackEngine.setPitchShift(semitones: pitchShiftSemitones)
        }
    }

    func resetPitchShiftToDefault() {
        setPitchShift(semitones: AppSliderDefaults.pitchShiftSemitones)
    }

    func toggleClick() {
        setClickEnabled(!isClickEnabled)
    }

    func setClickEnabled(_ isEnabled: Bool) {
        performUndoableEdit("Toggle Click") {
            isClickEnabled = isEnabled && canPlay && beatGridSettings.bpm != nil
            applyTempoMapToPlaybackEngine()
            playbackEngine.setClickEnabled(isClickEnabled)
        }
    }

    func setClickVolume(_ volume: Float) {
        performUndoableEdit("Change Click Volume") {
            applyClickVolume(volume)
        }
    }

    func resetClickVolumeToDefault() {
        performUndoableEdit("Reset Click Volume") {
            applyClickVolume(AppSliderDefaults.clickVolume)
        }
    }

    func applyClickVolume(_ volume: Float) {
        clickVolume = clampedVolume(volume)
        playbackEngine.setClickVolume(clickVolume)
    }

    func setMainTrackVolume(_ volume: Float) {
        performUndoableEdit("Change Main Volume") {
            mainTrackVolume = clampedVolume(volume)
            playbackEngine.setMainVolume(mainTrackVolume)
        }
    }

    func resetMainTrackVolumeToDefault() {
        setMainTrackVolume(AppSliderDefaults.mainTrackVolume)
    }

    func toggleLooping() {
        setLooping(!isLooping)
    }

    func startPlaybackClock() {
        guard playbackState == .playing else { return }
        guard clockTask == nil else { return }

        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPlaybackPosition()
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    func stopPlaybackClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func restorePlaybackMode(_ mode: PlaybackMode, preservedTime: TimeInterval) {
        if playbackEngine is MultiTrackAudioPlayer {
            beginPreparedPlaybackModeSwitch(
                mode,
                preservedTime: preservedTime,
                errorPrefix: "Playback mode restore failed",
                registersUndo: false
            )
            return
        }
        switchPlaybackMode(mode, preservedTime: preservedTime, errorPrefix: "Playback mode restore failed")
    }

    func beginPreparedPlaybackModeSwitch(
        _ mode: PlaybackMode,
        preservedTime: TimeInterval,
        errorPrefix: String,
        registersUndo: Bool
    ) {
        let targetMode: PlaybackMode = mode == .stems && canUseStemsPlayback ? .stems : .original
        guard targetMode != playbackMode || preparedPlaybackAssets[targetMode] == nil else { return }
        guard let importedFile else { return }

        audioPreparationTask?.cancel()
        let runID = UUID()
        let previousMode = playbackMode
        let wasPlaying = playbackState == .playing
        audioPreparationRunID = runID
        activePlaybackEngine.pause()
        videoFollower.pause()
        if wasPlaying {
            playbackState = .paused
        }

        audioPreparationState = AudioPreparationViewState(
            kind: .switchingMode,
            phase: .decoding,
            progress: 0,
            status: targetMode == .stems ? "Preparing stems" : "Preparing original audio",
            pendingPlaybackMode: targetMode,
            isCancellable: true
        )

        let preparer = playbackPreparer
        let stems = stemFiles
        let mixState = stemMixState
        let volume = mainTrackVolume
        let progressHandler: @Sendable (AudioPreparationProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard self?.audioPreparationRunID == runID else { return }
                self?.audioPreparationState = AudioPreparationViewState(
                    kind: .switchingMode,
                    phase: .decoding,
                    progress: progress.fractionCompleted,
                    status: progress.status,
                    pendingPlaybackMode: targetMode,
                    isCancellable: true
                )
            }
        }

        let task = Task {
            if let cached = preparedPlaybackAssets[targetMode] {
                return cached
            }
            if targetMode == .stems {
                return try await preparer.prepareStems(stems, mixState: mixState, progress: progressHandler)
            }
            return try await preparer.prepareOriginal(
                url: importedFile.url,
                volume: volume,
                progress: progressHandler
            )
        }
        audioPreparationTask = task

        Task { [weak self] in
            guard let self else { return }
            do {
                let asset = try await task.value
                try Task.checkCancellation()
                guard audioPreparationRunID == runID else { return }
                audioPreparationState = AudioPreparationViewState(
                    kind: .switchingMode,
                    phase: .installing,
                    progress: 1,
                    status: "Installing \(targetMode.title)",
                    pendingPlaybackMode: targetMode,
                    isCancellable: false
                )
                try configurePlayer(with: asset)
                preparedPlaybackAssets[targetMode] = asset
                playbackMode = targetMode
                seekExactly(to: preservedTime)

                if registersUndo, previousMode != targetMode {
                    undoManager?.registerUndo(withTarget: self) { target in
                        target.restorePlaybackMode(previousMode, preservedTime: preservedTime)
                    }
                    undoManager?.setActionName("Change Playback Mode")
                    refreshUndoAvailability()
                    refreshProjectModifiedState()
                }

                if wasPlaying {
                    try activePlaybackEngine.play()
                    videoFollower.play(rate: playbackRate)
                    playbackState = .playing
                }
                finishAudioPreparation()
            } catch {
                guard audioPreparationRunID == runID else { return }
                if wasPlaying, activePlaybackEngine.isLoaded {
                    try? activePlaybackEngine.play()
                    videoFollower.play(rate: playbackRate)
                    playbackState = .playing
                }
                audioPreparationTask = nil
                audioPreparationRunID = nil
                audioPreparationState = AudioPreparationViewState(
                    kind: .switchingMode,
                    phase: error is CancellationError ? .cancelled : .failed,
                    progress: nil,
                    status: error is CancellationError ? "Playback preparation cancelled" : error.localizedDescription,
                    pendingPlaybackMode: nil,
                    isCancellable: false
                )
                if !(error is CancellationError) {
                    errorMessage = "\(errorPrefix): \(error.localizedDescription)"
                }
            }
        }
    }

    func switchPlaybackMode(
        _ mode: PlaybackMode,
        preservedTime: TimeInterval,
        errorPrefix: String,
        reloadIfCurrentMode: Bool = false
    ) {
        let targetMode: PlaybackMode = mode == .stems && canUseStemsPlayback ? .stems : .original
        guard reloadIfCurrentMode || targetMode != playbackMode else { return }

        let wasPlaying = playbackState == .playing
        activePlaybackEngine.pause()
        videoFollower.pause()

        do {
            playbackMode = targetMode
            if targetMode == .stems {
                try loadStemPlaybackEngine()
            } else if let importedFile {
                try configurePlayer(with: importedFile)
            }

            if canPlay {
                seekExactly(to: preservedTime)
            } else {
                currentTime = preservedTime
            }

            if wasPlaying {
                do {
                    try activePlaybackEngine.play()
                    videoFollower.play(rate: playbackRate)
                    playbackState = .playing
                } catch {
                    playbackState = .paused
                    errorMessage = "Playback failed: \(error.localizedDescription)"
                }
            }
        } catch {
            let switchError = error
            playbackMode = .original
            if wasPlaying {
                playbackState = .paused
            }
            do {
                if let importedFile {
                    try configurePlayer(with: importedFile)
                    if canPlay {
                        seekExactly(to: preservedTime)
                    }
                }
            } catch {
                errorMessage = "\(errorPrefix): \(error.localizedDescription)"
                return
            }
            errorMessage = "\(errorPrefix): \(switchError.localizedDescription)"
        }
    }

    func configurePlayer(with file: ImportedAudioFile) throws {
        try playbackEngine.load(url: file.url)
        applyPlaybackConfiguration()
    }

    func configurePlayer(with preparedAsset: PreparedPlaybackAsset) throws {
        try playbackEngine.install(prepared: preparedAsset)
        applyPlaybackConfiguration()
    }

    func applyPlaybackConfiguration() {
        playbackEngine.setPlaybackRate(playbackRate)
        videoFollower.setPlaybackRate(playbackRate)
        playbackEngine.setPitchShift(semitones: pitchShiftSemitones)
        playbackEngine.setMainVolume(mainTrackVolume)
        playbackEngine.setClickVolume(clickVolume)
        playbackEngine.setClickSettings(beatGridSettings)
        playbackEngine.setTempoMap(tempoMap)
        playbackEngine.setClickSoundSettings(appSettingsStore.clickSoundSettings)
        playbackEngine.setClickEnabled(isClickEnabled && beatGridSettings.bpm != nil)
        applyAudioOutputDeviceSetting(appSettingsStore.audioDeviceSettings.outputDeviceUID)
        applyLoopConfiguration()
    }

    func applyAudioOutputDeviceSetting(_ outputDeviceUID: String?) {
        do {
            try playbackEngine.setAudioOutputDevice(uid: outputDeviceUID)
        } catch {
            errorMessage = "Audio output device failed: \(error.localizedDescription)"
        }
    }

    func refreshPlaybackPosition() {
        guard canPlay else { return }

        let engineTime = ProjectStateNormalizer.normalizedTimelineTime(activePlaybackEngine.currentTime, duration: duration)
        if abs(currentTime - engineTime) > Self.playbackTimePublishTolerance {
            currentTime = engineTime
        }
        updatePlaybackDisplayState(sampledTime: engineTime)
        videoFollower.sync(to: engineTime, isPlaying: playbackState == .playing, rate: playbackRate)

        if playbackState == .playing, (!activePlaybackEngine.isPlaying || engineTime >= duration), engineTime >= duration - 0.02 {
            stopPlaybackClock()
            playbackState = .stopped
            activePlaybackEngine.stop()
            videoFollower.stop()
            seekExactly(to: playbackMarkerTime)
            showPlaybackMarkerInTimeline()
            updatePlaybackDisplayState(sampledTime: currentTime)
            return
        }

        if playbackState == .playing, timelineViewport.shouldFollowPlaybackTime(engineTime) {
            let nextRange = timelineViewport
                .positionedWithTimeNearLeadingEdge(engineTime)
                .clampedRange
            if nextRange != timelineVisibleRange {
                timelineVisibleRange = nextRange
            }
        }
    }

    func applyLoopConfiguration() {
        playbackEngine.setLoop(enabled: isLooping, region: loopRegion)
    }

    func seekExactly(to time: TimeInterval) {
        guard canPlay else { return }

        let targetTime = max(0, min(time, duration))
        activePlaybackEngine.seek(to: targetTime)
        videoFollower.seek(to: targetTime)
        currentTime = targetTime
        updatePlaybackDisplayState(sampledTime: targetTime)
    }

    func setPlaybackMarkerExactly(to time: TimeInterval, shouldSeek: Bool = true) {
        let targetTime = ProjectStateNormalizer.normalizedTimelineTime(time, duration: duration)
        playbackMarkerTime = targetTime
        if shouldSeek, canPlay {
            activePlaybackEngine.seek(to: targetTime)
            videoFollower.seek(to: targetTime)
            currentTime = targetTime
        }
        updatePlaybackDisplayState(sampledTime: shouldSeek ? currentTime : playbackDisplayState.sampledTime)
    }

    func showPlaybackMarkerInTimeline() {
        timelineVisibleRange = timelineViewport
            .positionedWithTimeNearLeadingEdge(playbackMarkerTime)
            .clampedRange
    }

    var activePlaybackEngine: AudioPlaybackControlling {
        return playbackEngine
    }

    func updatePlaybackDisplayState(sampledTime: TimeInterval? = nil) {
        let nextState = PlaybackDisplayState(
            sampledTime: ProjectStateNormalizer.normalizedTimelineTime(sampledTime ?? currentTime, duration: duration),
            sampleDate: Date(),
            playbackRate: playbackRate,
            duration: duration,
            isPlaying: playbackState == .playing,
            isLooping: isLooping,
            loopRegion: loopRegion
        )

        if nextState != playbackDisplayState {
            playbackDisplayState = nextState
        }
    }

    private static let playbackTimePublishTolerance: TimeInterval = 0.000_5
}
