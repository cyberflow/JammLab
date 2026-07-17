import Foundation

extension AudioPlayerViewModel {
    var playbackRateText: String {
        "\(Int((playbackRate * 100).rounded()))%"
    }

    var pitchShiftText: String {
        let roundedSemitones = Int(pitchShiftSemitones.rounded())

        if roundedSemitones > 0 {
            return "+\(roundedSemitones) st"
        }

        return "\(roundedSemitones) st"
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
        switchPlaybackMode(mode, preservedTime: preservedTime, errorPrefix: "Playback mode restore failed")
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
