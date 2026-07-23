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
        conflictChoice: StemTranscriptionConflictChoice = .createNew,
        configuration: StemTranscriptionConfiguration = .neuralNoteDefaults
    ) {
        guard conflictChoice != .cancel,
              stemTranscriptionTasks[stemType] == nil,
              let stem = stemFiles.first(where: { $0.type == stemType })
        else { return }

        let existingTracks = stemTranscriptionTracks.filter { $0.stemType == stemType }
        guard existingTracks.isEmpty || conflictChoice == .replace || conflictChoice == .createNew else {
            return
        }

        let fingerprint: StemSourceFingerprint
        do {
            fingerprint = try stemSeparationService.sourceFingerprint(for: stem.url)
        } catch {
            stemTranscriptionStates[stemType] = StemTranscriptionViewState(
                phase: .failed,
                status: StemTranscriptionError.stemAudioUnavailable.localizedDescription
            )
            errorMessage = StemTranscriptionError.stemAudioUnavailable.localizedDescription
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

                guard !Task.isCancelled,
                      stemTranscriptionRunIDs[stemType] == runID,
                      currentProjectURL == capturedProjectURL,
                      importedFile?.url == capturedImportedFileURL,
                      let currentStem = stemFiles.first(where: { $0.type == stemType }),
                      currentStem.url == stem.url
                else {
                    throw StemTranscriptionError.sourceStemChanged
                }

                let currentFingerprint = try stemSeparationService.sourceFingerprint(for: currentStem.url)
                guard currentFingerprint.hasSameFileIdentity(as: fingerprint) else {
                    throw StemTranscriptionError.sourceStemChanged
                }

                let mapped = try StemTranscriptionNotationMapper.map(
                    result: result,
                    stemType: stemType,
                    sourceFingerprint: fingerprint,
                    timelineMapping: .aligned(duration: duration),
                    configuration: configuration,
                    tempoMap: tempoMap,
                    projectDuration: duration,
                    keyName: effectiveKeyName
                )
                guard stemTranscriptionRunIDs[stemType] == runID else {
                    throw StemTranscriptionError.cancelled
                }

                performUndoableEdit("Transcribe \(stemType.title)") {
                    if conflictChoice == .replace {
                        let removedIDs = Set(
                            self.stemTranscriptionTracks
                                .filter { $0.stemType == stemType }
                                .flatMap { $0.notationItemIDs }
                        )
                        self.notationItems.removeAll { removedIDs.contains($0.id) }
                        self.stemTranscriptionTracks.removeAll { $0.stemType == stemType }
                    }
                    self.notationItems.append(contentsOf: mapped.notationItems)
                    self.stemTranscriptionTracks.append(mapped.track)
                    self.visibleNotationPartIDs.insert(.stem(stemType))
                    self.stemNotationTrackCollapsed[stemType] = false
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
