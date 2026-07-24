import Foundation

extension AudioPlayerViewModel {
    func hasStemTranscription(for stemType: StemType) -> Bool {
        stemTranscriptionTracks.contains { $0.stemType == stemType }
    }

    func stemTranscriptionState(for stemType: StemType) -> StemTranscriptionViewState {
        stemTranscriptionStates[stemType] ?? StemTranscriptionViewState()
    }

    func transcribeStem(
        _ stemType: StemType,
        configuration: StemTranscriptionConfiguration = .neuralNoteDefaults
    ) {
        guard stemType.supportsBasicPitchTranscription,
              stemTranscriptionTasks[stemType] == nil,
              let stem = stemFile(for: stemType)
        else { return }

        let sourceFingerprint: StemSourceFingerprint
        do {
            sourceFingerprint = try stemSourceFingerprint(for: stem)
        } catch {
            errorMessage = StemTranscriptionError.stemAudioUnavailable.localizedDescription
            return
        }

        if hasMeaningfulStemNotationContent(for: stemType) {
            pendingStemTranscriptionOverwrite = makeOverwriteRequest(
                stemType: stemType,
                stem: stem,
                sourceFingerprint: sourceFingerprint,
                configuration: configuration
            )
            return
        }

        startStemTranscription(stemType, configuration: configuration)
    }

    func confirmPendingStemTranscriptionOverwrite() {
        guard let request = pendingStemTranscriptionOverwrite else { return }
        pendingStemTranscriptionOverwrite = nil
        guard isCurrentOverwriteRequest(request) else { return }
        startStemTranscription(request.stemType, configuration: request.configuration)
    }

    func cancelPendingStemTranscriptionOverwrite() {
        pendingStemTranscriptionOverwrite = nil
    }

    func hasMeaningfulStemNotationContent(for stemType: StemType) -> Bool {
        notationItems.contains {
            $0.partID.stemType == stemType && !$0.isSynthesized
        } || stemTranscriptionTracks.contains {
            $0.stemType == stemType && !$0.notes.isEmpty
        }
    }

    private func startStemTranscription(
        _ stemType: StemType,
        configuration: StemTranscriptionConfiguration
    ) {
        guard let stem = stemFile(for: stemType) else { return }

        let fingerprint: StemSourceFingerprint
        do {
            fingerprint = try stemSourceFingerprint(for: stem)
        } catch {
            failStemTranscriptionAsUnavailable(stemType)
            return
        }

        let runID = UUID()
        let operation = StemTranscriptionOperation()
        let capturedProjectURL = currentProjectURL
        let capturedImportedFileURL = importedFile?.url
        stemTranscriptionRunIDs[stemType] = runID
        stemTranscriptionOperations[stemType] = operation
        stemTranscriptionStates[stemType] = StemTranscriptionViewState(
            phase: .preparingAudio,
            progress: 0,
            status: "Preparing audio"
        )

        stemTranscriptionTasks[stemType] = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await stemTranscriptionService.transcribe(
                    stemType: stemType,
                    stemURL: stem.url,
                    configuration: configuration,
                    operation: operation
                ) { [weak self] phase, progress in
                    Task { @MainActor in
                        guard self?.stemTranscriptionRunIDs[stemType] == runID else { return }
                        self?.stemTranscriptionStates[stemType] = StemTranscriptionViewState(
                            phase: phase,
                            progress: progress,
                            status: Self.transcriptionStatus(for: phase)
                        )
                    }
                }

                try validateStemTranscriptionRunContext(
                    stemType: stemType,
                    runID: runID,
                    stem: stem,
                    projectURL: capturedProjectURL,
                    importedFileURL: capturedImportedFileURL,
                    sourceFingerprint: fingerprint
                )

                let trackID = UUID()
                let notationPartID = NotationPartID.stem(stemType)
                let mapped = try StemTranscriptionNotationMapper.map(
                    result: result,
                    stemType: stemType,
                    trackID: trackID,
                    notationPartID: notationPartID,
                    sourceFingerprint: fingerprint,
                    timelineMapping: .aligned(duration: duration),
                    configuration: configuration,
                    tempoMap: tempoMap,
                    projectDuration: duration,
                    keyName: effectiveKeyName
                )
                try validateStemTranscriptionRunIsActive(stemType: stemType, runID: runID)

                performUndoableEdit("Transcribe \(stemType.title)") {
                    self.replaceStemTranscriptionContent(stemType: stemType, with: mapped)
                }
                stemTranscriptionStates[stemType] = StemTranscriptionViewState(
                    phase: .completed,
                    progress: 1,
                    status: "\(mapped.track.notes.count) notes transcribed"
                )
                finishStemTranscription(stemType, runID: runID)
            } catch {
                guard stemTranscriptionRunIDs[stemType] == runID else { return }
                let transcriptionError = (error as? StemTranscriptionError)
                    ?? (operation.isCancelled || Task.isCancelled ? .cancelled : .inferenceFailed)
                let isCancellation = transcriptionError == .cancelled
                stemTranscriptionStates[stemType] = StemTranscriptionViewState(
                    phase: isCancellation ? .cancelled : .failed,
                    progress: 0,
                    status: transcriptionError.localizedDescription
                )
                if !isCancellation {
                    errorMessage = transcriptionError.localizedDescription
                }
                finishStemTranscription(stemType, runID: runID)
            }
        }
    }

    private func stemFile(for stemType: StemType) -> StemFile? {
        stemFiles.first { $0.type == stemType }
    }

    private func stemSourceFingerprint(for stem: StemFile) throws -> StemSourceFingerprint {
        try stemSeparationService.sourceFingerprint(for: stem.url)
    }

    private func makeOverwriteRequest(
        stemType: StemType,
        stem: StemFile,
        sourceFingerprint: StemSourceFingerprint,
        configuration: StemTranscriptionConfiguration
    ) -> StemTranscriptionOverwriteRequest {
        StemTranscriptionOverwriteRequest(
            stemType: stemType,
            projectURL: currentProjectURL,
            importedFileURL: importedFile?.url,
            stemURL: stem.url,
            sourceFingerprint: sourceFingerprint,
            configuration: configuration
        )
    }

    private func isCurrentOverwriteRequest(_ request: StemTranscriptionOverwriteRequest) -> Bool {
        guard request.stemType.supportsBasicPitchTranscription,
              stemTranscriptionTasks[request.stemType] == nil,
              currentProjectURL == request.projectURL,
              importedFile?.url == request.importedFileURL,
              stemFile(for: request.stemType)?.url == request.stemURL
        else {
            return false
        }

        return (try? stemSeparationService.sourceFingerprint(for: request.stemURL))
            .map { $0.hasSameFileIdentity(as: request.sourceFingerprint) } == true
    }

    private func failStemTranscriptionAsUnavailable(_ stemType: StemType) {
        stemTranscriptionStates[stemType] = StemTranscriptionViewState(
            phase: .failed,
            status: StemTranscriptionError.stemAudioUnavailable.localizedDescription
        )
        errorMessage = StemTranscriptionError.stemAudioUnavailable.localizedDescription
    }

    private func validateStemTranscriptionRunContext(
        stemType: StemType,
        runID: UUID,
        stem: StemFile,
        projectURL: URL?,
        importedFileURL: URL?,
        sourceFingerprint: StemSourceFingerprint
    ) throws {
        guard !Task.isCancelled,
              stemTranscriptionRunIDs[stemType] == runID,
              currentProjectURL == projectURL,
              importedFile?.url == importedFileURL,
              let currentStem = stemFile(for: stemType),
              currentStem.url == stem.url
        else {
            throw StemTranscriptionError.sourceStemChanged
        }

        let currentFingerprint = try stemSourceFingerprint(for: currentStem)
        guard currentFingerprint.hasSameFileIdentity(as: sourceFingerprint) else {
            throw StemTranscriptionError.sourceStemChanged
        }
    }

    private func validateStemTranscriptionRunIsActive(stemType: StemType, runID: UUID) throws {
        guard stemTranscriptionRunIDs[stemType] == runID else {
            throw StemTranscriptionError.cancelled
        }
    }

    private func replaceStemTranscriptionContent(
        stemType: StemType,
        with output: StemTranscriptionNotationOutput
    ) {
        let removedPartIDs = Set(
            notationItems
                .filter { $0.partID.stemType == stemType }
                .map(\.partID)
        ).union(
            stemTranscriptionTracks
                .filter { $0.stemType == stemType }
                .map(\.notationPartID)
        )
        notationItems.removeAll { $0.partID.stemType == stemType }
        stemTranscriptionTracks.removeAll { $0.stemType == stemType }
        visibleNotationPartIDs.subtract(removedPartIDs)
        notationItems.append(contentsOf: output.notationItems)
        stemTranscriptionTracks.append(output.track)
        visibleNotationPartIDs.insert(output.track.notationPartID)
        stemNotationTrackCollapsed[stemType] = false
    }

    func cancelStemTranscription(_ stemType: StemType) {
        stemTranscriptionOperations[stemType]?.cancel()
        stemTranscriptionTasks[stemType]?.cancel()
        guard stemTranscriptionTasks[stemType] != nil else { return }
        stemTranscriptionStates[stemType] = StemTranscriptionViewState(
            phase: .cancelled,
            progress: 0,
            status: "Cancelling transcription"
        )
    }

    func exportLatestStemTranscriptionMIDI(_ stemType: StemType) {
        guard let track = stemTranscriptionTracks
            .filter({ $0.stemType == stemType })
            .max(by: { $0.createdAt < $1.createdAt })
        else {
            errorMessage = "There is no \(stemType.title) transcription to export."
            return
        }
        let sourceName = (importedFile?.displayName as NSString?)?.deletingPathExtension
            ?? "Transcription"
        guard let url = stemTranscriptionMIDIDocumentService.chooseExportURL(
            defaultName: "\(sourceName)-\(stemType.rawValue)-transcription.mid"
        ) else {
            return
        }
        do {
            let data = StemTranscriptionMIDIExporter.data(
                for: track,
                tempoBPM: beatGridSettings.bpm ?? AppDefaults.defaultTempoBPM
            )
            try stemTranscriptionMIDIDocumentService.save(data, to: url)
        } catch {
            errorMessage = "MIDI export failed: \(error.localizedDescription)"
        }
    }

    private func finishStemTranscription(_ stemType: StemType, runID: UUID) {
        guard stemTranscriptionRunIDs[stemType] == runID else { return }
        stemTranscriptionRunIDs[stemType] = nil
        stemTranscriptionOperations[stemType] = nil
        stemTranscriptionTasks[stemType] = nil
    }

    private static func transcriptionStatus(for phase: StemTranscriptionPhase) -> String {
        switch phase {
        case .preparingAudio:
            return "Preparing audio"
        case .loadingModel:
            return "Loading model"
        case .transcribing:
            return "Transcribing"
        case .processingNotes:
            return "Processing notes"
        case .completed:
            return "Completed"
        case .failed:
            return "Transcription failed"
        case .cancelled:
            return "Transcription cancelled"
        case .idle:
            return ""
        }
    }
}
