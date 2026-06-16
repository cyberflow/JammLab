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
            try activePlaybackEngine.play()
            videoFollower.play(rate: playbackRate)
            playbackState = .playing
        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard canPlay else { return }
        activePlaybackEngine.pause()
        videoFollower.pause()
        currentTime = activePlaybackEngine.currentTime
        playbackState = .paused
    }

    func stop() {
        guard canPlay else { return }
        activePlaybackEngine.stop()
        videoFollower.stop()
        currentTime = 0
        playbackState = .stopped
    }

    func togglePlayPause() {
        guard canPlay else { return }

        if playbackState == .playing {
            pause()
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
    }

    func seekToStart() {
        seekExactly(to: 0)
    }

    func seekToEnd() {
        guard canPlay else { return }

        if playbackState == .playing {
            activePlaybackEngine.pause()
            playbackState = .paused
        }

        seekExactly(to: duration)
    }

    func setLooping(_ isEnabled: Bool) {
        performUndoableEdit("Toggle Loop") {
            isLooping = isEnabled
            applyLoopConfiguration()
        }
    }

    func setPlaybackRate(_ rate: Float) {
        performUndoableEdit("Change Speed") {
            playbackRate = min(1, max(0.25, rate))
            playbackEngine.setPlaybackRate(playbackRate)
            videoFollower.setPlaybackRate(playbackRate)
        }
    }

    func resetPlaybackRateToDefault() {
        setPlaybackRate(AppSliderDefaults.playbackRate)
    }

    func setPitchShift(semitones: Float) {
        performUndoableEdit("Change Pitch") {
            pitchShiftSemitones = min(12, max(-12, semitones))
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
            applyClickVolume(volume, shouldPersist: false)
        }
    }

    func resetClickVolumeToDefault() {
        performUndoableEdit("Reset Click Volume") {
            applyClickVolume(AppSliderDefaults.clickVolume, shouldPersist: false)
        }
    }

    func applyClickVolume(_ volume: Float, shouldPersist: Bool) {
        clickVolume = min(1, max(0, volume))
        playbackEngine.setClickVolume(clickVolume)
        guard shouldPersist else { return }
        UserDefaults.standard.set(clickVolume, forKey: "metronome.volume")
    }

    func setMainTrackVolume(_ volume: Float) {
        performUndoableEdit("Change Main Volume") {
            mainTrackVolume = min(1, max(0, volume))
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
        let targetMode: PlaybackMode = mode == .stems && canUseStemsPlayback ? .stems : .original
        guard targetMode != playbackMode else { return }

        let wasPlaying = playbackState == .playing
        activePlaybackEngine.pause()

        do {
            playbackMode = targetMode
            if targetMode == .stems {
                try loadStemPlaybackEngine()
            } else if let importedFile {
                try configurePlayer(with: importedFile)
            }

            if canPlay {
                activePlaybackEngine.seek(to: preservedTime)
            }
            currentTime = preservedTime

            if wasPlaying {
                play()
            }
        } catch {
            playbackMode = .original
            errorMessage = "Playback mode restore failed: \(error.localizedDescription)"
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

        currentTime = activePlaybackEngine.currentTime
        videoFollower.sync(to: currentTime, isPlaying: playbackState == .playing, rate: playbackRate)

        if playbackState == .playing, (!activePlaybackEngine.isPlaying || currentTime >= duration), currentTime >= duration - 0.02 {
            playbackState = .stopped
            currentTime = 0
            activePlaybackEngine.stop()
            videoFollower.stop()
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
    }

    var activePlaybackEngine: AudioPlaybackControlling {
        return playbackEngine
    }
}
