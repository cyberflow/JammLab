import Foundation

extension AudioPlayerViewModel {
    func analyze(
        file: ImportedAudioFile,
        includesTempo: Bool = true,
        includesKey: Bool = true,
        marksProjectModifiedForAutoKey: Bool = false
    ) {
        guard includesTempo || includesKey else {
            analysisTask?.cancel()
            analysisTask = nil
            isAnalyzing = false
            analysisResult = nil
            return
        }

        analysisTask?.cancel()
        isAnalyzing = true
        analysisResult = nil
        let keySelectionAtStart = projectKeySelection

        analysisTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await analyzer.analyze(
                    url: file.url,
                    includesTempo: includesTempo,
                    includesKey: includesKey
                )
                guard !Task.isCancelled else { return }
                analysisResult = result

                if includesKey,
                   keySelectionAtStart == nil,
                   projectKeySelection == nil,
                   let detectedKey = ProjectKeySelection.detected(
                    from: result.keyName,
                    confidence: result.keyConfidence
                   ) {
                    projectKeySelection = detectedKey
                    if marksProjectModifiedForAutoKey {
                        refreshProjectModifiedState()
                    } else if !isProjectModified {
                        markProjectClean()
                    } else {
                        refreshProjectModifiedState()
                    }
                }

                if includesTempo, shouldAcceptAnalyzedTempo, let analyzedBPM = result.bpm {
                    synchronizeTempoBPM(Double(analyzedBPM))
                    beatGridSettings.automaticFirstBeatTime = 0
                    beatGridSettings.firstBeatTime = 0
                    beatGridSettings.alignmentSource = .automatic
                    beatGridSettings.lastChangedAt = Date()
                    clearNotationMeasureSelection()
                    applyTempoMapToPlaybackEngine()
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
}
