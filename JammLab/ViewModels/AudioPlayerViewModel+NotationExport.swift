import Foundation

extension AudioPlayerViewModel {
    var canExportNotation: Bool {
        guard let firstVisiblePart = visibleNotationParts.first else { return false }
        let score = currentNotationExportScore(for: firstVisiblePart.id)
        return score.isReady && !score.measures.isEmpty
    }

    @discardableResult
    func exportNotationAsMusicXML() async -> Bool {
        errorMessage = nil
        let format = NotationExportFormat.musicXML
        let request: NotationExportRequest

        do {
            request = try makeNotationExportRequest()
            _ = try notationExportService.export(request, format: format)
        } catch {
            errorMessage = "Notation export failed: \(error.localizedDescription)"
            return false
        }

        guard let url = notationExportDocumentService.chooseExportURL(
            defaultName: defaultNotationExportFilename(for: format),
            format: format
        ) else {
            return false
        }

        return await exportNotation(request, format: format, to: url)
    }

    @discardableResult
    func exportNotation(format: NotationExportFormat, to url: URL) async -> Bool {
        do {
            let request = try makeNotationExportRequest()
            return await exportNotation(request, format: format, to: url)
        } catch {
            errorMessage = "Notation export failed: \(error.localizedDescription)"
            return false
        }
    }

    private func exportNotation(
        _ request: NotationExportRequest,
        format: NotationExportFormat,
        to url: URL
    ) async -> Bool {
        errorMessage = nil

        do {
            let data = try notationExportService.export(request, format: format)
            try notationExportDocumentService.save(data, to: url)
            return true
        } catch {
            errorMessage = "Notation export failed: \(error.localizedDescription)"
            return false
        }
    }

    private func makeNotationExportRequest() throws -> NotationExportRequest {
        let parts = currentNotationExportParts()
        guard let firstPart = parts.first else {
            throw NotationExportError.emptyScore
        }

        return NotationExportRequest(
            displayName: notationExportDisplayName,
            score: firstPart.score,
            parts: parts,
            tempoBPM: beatGridSettings.bpm
        )
    }

    private func currentNotationExportScore(for partID: NotationPartID) -> NotationScoreState {
        NotationViewportFactory().scoreState(
            tempoMap: tempoMap,
            duration: duration,
            currentTime: currentTime,
            playbackMarkerTime: playbackMarkerTime,
            isPlaying: playbackState == .playing,
            keyName: effectiveKeyName,
            partID: partID,
            includesHarmonies: partID.isMain,
            notationItems: notationItems,
            harmonySymbols: harmonySymbols,
            notes: notes
        )
    }

    private func currentNotationExportParts() -> [NotationExportPart] {
        visibleNotationParts.compactMap { part in
            let score = currentNotationExportScore(for: part.id)
            guard score.isReady, !score.measures.isEmpty else { return nil }
            return NotationExportPart(descriptor: part, score: score)
        }
    }

    private var notationExportDisplayName: String {
        (importedFile?.displayName as NSString?)?.deletingPathExtension ?? "Notation"
    }

    private func defaultNotationExportFilename(for format: NotationExportFormat) -> String {
        "\(notationExportDisplayName).\(format.fileExtension)"
    }
}
