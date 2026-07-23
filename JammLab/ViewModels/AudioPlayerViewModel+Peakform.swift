import Foundation

extension AudioPlayerViewModel {
    func buildPeakform(file: ImportedAudioFile) {
        waveformTask?.cancel()
        isBuildingWaveform = true
        peakformData = nil

        if let currentProjectURL,
           let projectPeakform = try? projectArtifactStore.readMainPeakform(projectURL: currentProjectURL) {
            peakformData = projectPeakform
            isBuildingWaveform = false
            return
        }

        waveformTask = Task { [weak self] in
            guard let self else { return }

            do {
                let peakform = try await peakformProvider.peakform(for: file.url)
                guard !Task.isCancelled else { return }
                peakformData = peakform
                isBuildingWaveform = false
                if let currentProjectURL {
                    try? projectArtifactStore.writeMainPeakform(peakform, projectURL: currentProjectURL)
                    await peakformProvider.removeCachedPeakform(for: file.url)
                }
            } catch {
                guard !Task.isCancelled else { return }
                isBuildingWaveform = false
                errorMessage = "Peakform failed: \(error.localizedDescription)"
            }
        }
    }
}
