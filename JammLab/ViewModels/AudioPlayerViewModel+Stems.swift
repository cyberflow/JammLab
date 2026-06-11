import Foundation

extension AudioPlayerViewModel {
    var canUseStemsPlayback: Bool {
        !stemFiles.isEmpty
    }

    func separateStems() {
        guard let importedFile else {
            stemSeparationState = StemSeparationViewState(
                phase: .failed(StemSeparationError.missingAudioFile.localizedDescription),
                progress: nil,
                status: StemSeparationError.missingAudioFile.localizedDescription
            )
            return
        }

        guard stemSeparationTask == nil else { return }

        clearStemPeakforms()

        stemSeparationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let metadata = try await stemSeparationService.separate(
                    audioURL: importedFile.url,
                    originalDuration: importedFile.duration
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.stemSeparationState = StemSeparationViewState(
                            phase: progress.phase,
                            progress: progress.progress,
                            status: progress.status
                        )
                    }
                }

                guard !Task.isCancelled else { throw StemSeparationError.cancelled }
                let persistedMetadata = try persistStemArtifactsIfNeeded(metadata)
                registerStemMetadata(persistedMetadata)
                refreshProjectModifiedState()
                stemSeparationTask = nil
            } catch {
                let message = error.localizedDescription
                let diagnostics = (error as? StemSeparationError)?.diagnostics
                stemSeparationState = StemSeparationViewState(
                    phase: error is CancellationError ? .cancelled : .failed(message),
                    progress: nil,
                    status: message,
                    diagnostics: diagnostics
                )
                if !(error is CancellationError) {
                    errorMessage = message
                }
                stemSeparationTask = nil
            }
        }
    }

    func cancelStemSeparation() {
        stemSeparationTask?.cancel()
        stemSeparationTask = nil
        clearStemPeakforms()
        stemSeparationService.cancel()
        stemSeparationState = StemSeparationViewState(
            phase: .cancelled,
            progress: nil,
            status: "Stem separation cancelled"
        )
    }

    func retryStemSeparation() {
        separateStems()
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        let targetMode: PlaybackMode = mode == .stems && !canUseStemsPlayback ? .original : mode

        performUndoableEdit("Change Playback Mode") {
            guard targetMode != playbackMode else { return }

            let wasPlaying = playbackState == .playing
            let preservedTime = currentTime
            activePlaybackEngine.pause()

            do {
                playbackMode = targetMode
                if targetMode == .stems {
                    try loadStemPlaybackEngine()
                } else if let importedFile {
                    try configurePlayer(with: importedFile)
                    playbackEngine.seek(to: preservedTime)
                }
            } catch {
                let switchError = error
                playbackMode = .original
                do {
                    if let importedFile {
                        try configurePlayer(with: importedFile)
                        playbackEngine.seek(to: preservedTime)
                    }
                } catch let restoreError {
                    errorMessage = "Playback mode switch failed: \(restoreError.localizedDescription)"
                    return
                }
                errorMessage = "Playback mode switch failed: \(switchError.localizedDescription)"
                return
            }

            activePlaybackEngine.seek(to: preservedTime)
            currentTime = preservedTime

            if wasPlaying {
                play()
            }
        }
    }

    func togglePlaybackMode() {
        guard canUseStemsPlayback else {
            setPlaybackMode(.original)
            return
        }

        setPlaybackMode(playbackMode == .stems ? .original : .stems)
    }

    func setStemVolume(_ type: StemType, volume: Float) {
        performUndoableEdit("Change Stem Volume") {
            stemMixState.update(type) { item in
                item.volume = volume
            }
            playbackEngine.applyMix(stemMixState)
        }
    }

    func resetStemVolumeToDefault(_ type: StemType) {
        setStemVolume(type, volume: AppSliderDefaults.stemTrackVolume)
    }

    func toggleStemMute(_ type: StemType) {
        performUndoableEdit("Toggle Stem Mute") {
            stemMixState.update(type) { item in
                item.isMuted.toggle()
            }
            playbackEngine.applyMix(stemMixState)
        }
    }

    func toggleStemSolo(_ type: StemType) {
        performUndoableEdit("Toggle Stem Solo") {
            stemMixState.update(type) { item in
                item.isSoloed.toggle()
            }
            playbackEngine.applyMix(stemMixState)
        }
    }


    func registerStemMetadata(_ metadata: StemCacheMetadata) {
        stemCacheMetadata = metadata
        stemFiles = metadata.stems
        stemMixState.setAvailability(from: metadata.stems)
        buildStemPeakforms(for: metadata.stems)
        stemSeparationState = StemSeparationViewState(
            phase: .completed,
            progress: 1,
            status: "Stems ready"
        )

        if playbackMode == .stems {
            do {
                try loadStemPlaybackEngine()
            } catch {
                playbackMode = .original
                errorMessage = "Stem playback failed: \(error.localizedDescription)"
            }
        }
    }

    func restoreCachedStems(
        for audioURL: URL,
        preferredMixState: StemMixState? = nil,
        preferredPlaybackMode: PlaybackMode = .original
    ) -> Bool {
        do {
            guard let metadata = try stemSeparationService.cachedResult(for: audioURL) else {
                return false
            }

            if let preferredMixState {
                stemMixState = preferredMixState
            }

            if preferredPlaybackMode == .stems {
                playbackMode = .stems
            }
            registerStemMetadata(metadata)

            return true
        } catch {
            stemSeparationState = StemSeparationViewState(
                phase: .failed(error.localizedDescription),
                progress: nil,
                status: "Stems unavailable: \(error.localizedDescription)"
            )
            return false
        }
    }

    func loadStemPlaybackEngine() throws {
        guard !stemFiles.isEmpty else { return }

        try playbackEngine.load(stems: stemFiles, mixState: stemMixState)
        applyPlaybackConfiguration()
        playbackEngine.seek(to: currentTime)
    }

    func restoreStemState(_ projectStemState: StemProjectState?, audioURL: URL, projectURL: URL?) {
        resetStemState(mixState: projectStemState?.mixState ?? StemMixState())

        if let projectURL, projectStemState != nil {
            do {
                let currentFingerprint = try? stemSeparationService.sourceFingerprint(for: audioURL)
                if let metadata = try projectArtifactStore.readStemMetadata(
                    projectURL: projectURL,
                    expectedFingerprint: currentFingerprint,
                    fallbackFingerprint: projectStemState?.sourceFingerprint
                ) {
                    if projectStemState?.playbackMode == .stems {
                        playbackMode = .stems
                    }
                    registerStemMetadata(metadata)
                    return
                }
            } catch {
                stemSeparationState = StemSeparationViewState(
                    phase: .failed(error.localizedDescription),
                    progress: nil,
                    status: "Stems unavailable: \(error.localizedDescription)"
                )
            }
        }

        guard
            let projectStemState,
            let cacheKey = projectStemState.cacheKey,
            let fingerprint = projectStemState.sourceFingerprint
        else {
            if !restoreCachedStems(
                for: audioURL,
                preferredMixState: projectStemState?.mixState,
                preferredPlaybackMode: projectStemState?.playbackMode ?? .original
            ) {
                stemSeparationState = StemSeparationViewState()
            }
            return
        }

        do {
            let currentFingerprint = try stemSeparationService.sourceFingerprint(for: audioURL)
            guard currentFingerprint == fingerprint else {
                if !restoreCachedStems(
                    for: audioURL,
                    preferredMixState: projectStemState.mixState,
                    preferredPlaybackMode: projectStemState.playbackMode
                ) {
                    stemSeparationState = StemSeparationViewState(
                        phase: .failed("Source audio changed"),
                        progress: nil,
                        status: "Stems unavailable: source audio changed"
                    )
                }
                return
            }

            guard let metadata = try stemSeparationService.cachedResult(cacheKey: cacheKey, expectedFingerprint: fingerprint) else {
                if !restoreCachedStems(
                    for: audioURL,
                    preferredMixState: projectStemState.mixState,
                    preferredPlaybackMode: projectStemState.playbackMode
                ) {
                    stemSeparationState = StemSeparationViewState(
                        phase: .failed("Stem cache missing"),
                        progress: nil,
                        status: "Stems unavailable: cache missing"
                    )
                }
                return
            }

            stemFiles = metadata.stems
            stemCacheMetadata = metadata
            stemMixState.setAvailability(from: metadata.stems)
            buildStemPeakforms(for: metadata.stems)
            if projectStemState.playbackMode == .stems {
                playbackMode = .stems
            }
            stemSeparationState = StemSeparationViewState(
                phase: .completed,
                progress: 1,
                status: "Stems ready"
            )
            if playbackMode == .stems {
                try loadStemPlaybackEngine()
            }
        } catch {
            stemSeparationState = StemSeparationViewState(
                phase: .failed(error.localizedDescription),
                progress: nil,
                status: "Stems unavailable: \(error.localizedDescription)"
            )
        }
    }

    func makeStemProjectState() -> StemProjectState? {
        guard !stemFiles.isEmpty, let stemCacheMetadata else {
            return StemProjectState(playbackMode: .original, mixState: stemMixState)
        }

        return StemProjectState(
            cacheKey: stemCacheMetadata.cacheKey,
            sourceFingerprint: stemCacheMetadata.sourceFingerprint,
            backendIdentifier: stemCacheMetadata.backendIdentifier,
            modelName: stemCacheMetadata.modelName,
            settingsVersion: stemCacheMetadata.settingsVersion,
            playbackMode: playbackMode,
            mixState: stemMixState
        )
    }

    func resetStemState(mixState: StemMixState = StemMixState()) {
        playbackMode = .original
        stemFiles = []
        clearStemPeakforms()
        stemMixState = mixState
        stemSeparationState = StemSeparationViewState()
        stemCacheMetadata = nil
    }

    func clearStemPeakforms() {
        stemPeakformTask?.cancel()
        stemPeakformTask = nil
        stemPeakforms = [:]
        isBuildingStemPeakforms = false
    }

    func buildStemPeakforms(for stems: [StemFile]) {
        stemPeakformTask?.cancel()
        stemPeakforms = [:]

        guard !stems.isEmpty else {
            isBuildingStemPeakforms = false
            return
        }

        isBuildingStemPeakforms = true

        stemPeakformTask = Task { [weak self] in
            guard let self else { return }

            var nextPeakforms: [StemType: PeakformData] = [:]
            var lastError: Error?

            for stem in stems {
                do {
                    let peakform: PeakformData
                    if let currentProjectURL,
                       let projectPeakform = try? projectArtifactStore.readStemPeakform(
                        type: stem.type,
                        projectURL: currentProjectURL
                       ) {
                        peakform = projectPeakform
                    } else {
                        peakform = try await peakformProvider.peakform(for: stem.url)
                        if let currentProjectURL {
                            try? projectArtifactStore.writeStemPeakforms([stem.type: peakform], projectURL: currentProjectURL)
                            await peakformProvider.removeCachedPeakform(for: stem.url)
                        }
                    }
                    guard !Task.isCancelled else { return }
                    nextPeakforms[stem.type] = peakform
                    stemPeakforms = nextPeakforms
                } catch {
                    guard !Task.isCancelled else { return }
                    lastError = error
                }
            }

            isBuildingStemPeakforms = false
            stemPeakformTask = nil

            if nextPeakforms.isEmpty, let lastError {
                errorMessage = "Stem peakform failed: \(lastError.localizedDescription)"
            }
        }
    }
}
