import Foundation

struct ProjectArtifactStore {
    static let stemsDirectoryName = "stems"
    static let peaksDirectoryName = "peaks"
    static let mediaDirectoryName = "media"
    static let mainPeakformFilename = "main.peakform"
    static let metadataFilename = "metadata.json"
    static let extractedVideoAudioFilename = "audio.m4a"

    private let fileManager: FileManager
    private let peakformCache = PeakformBinaryCache()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func artifactRoot(for projectURL: URL) -> URL {
        projectURL.deletingLastPathComponent()
    }

    func ensureArtifactRoot(for projectURL: URL) throws {
        try fileManager.createDirectory(at: artifactRoot(for: projectURL), withIntermediateDirectories: true)
    }

    func ensureArtifactDirectories(for projectURL: URL) throws {
        try ensureArtifactRoot(for: projectURL)
        try fileManager.createDirectory(at: stemsDirectory(for: projectURL), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: peaksDirectory(for: projectURL), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mediaDirectory(for: projectURL), withIntermediateDirectories: true)
    }

    func stemsDirectory(for projectURL: URL) -> URL {
        artifactRoot(for: projectURL).appendingPathComponent(Self.stemsDirectoryName, isDirectory: true)
    }

    func peaksDirectory(for projectURL: URL) -> URL {
        artifactRoot(for: projectURL).appendingPathComponent(Self.peaksDirectoryName, isDirectory: true)
    }

    func mediaDirectory(for projectURL: URL) -> URL {
        artifactRoot(for: projectURL).appendingPathComponent(Self.mediaDirectoryName, isDirectory: true)
    }

    func writeMainPeakform(_ peakform: PeakformData, projectURL: URL) throws {
        try fileManager.createDirectory(at: peaksDirectory(for: projectURL), withIntermediateDirectories: true)
        try peakformCache.write(peakform, to: mainPeakformURL(for: projectURL))
    }

    func readMainPeakform(projectURL: URL) throws -> PeakformData? {
        let url = mainPeakformURL(for: projectURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try peakformCache.read(from: url)
    }

    func writeStemPeakforms(_ peakforms: [StemType: PeakformData], projectURL: URL) throws {
        guard !peakforms.isEmpty else { return }
        try fileManager.createDirectory(at: peaksDirectory(for: projectURL), withIntermediateDirectories: true)
        for (type, peakform) in peakforms {
            try peakformCache.write(peakform, to: stemPeakformURL(for: type, projectURL: projectURL))
        }
    }

    func readStemPeakform(type: StemType, projectURL: URL) throws -> PeakformData? {
        let url = stemPeakformURL(for: type, projectURL: projectURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try peakformCache.read(from: url)
    }

    func writeStemMetadata(_ metadata: StemCacheMetadata, projectURL: URL) throws -> StemCacheMetadata {
        let directory = stemsDirectory(for: projectURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var localMetadata = metadata
        localMetadata.stems = try metadata.stems.map { stem in
            let destination = directory.appendingPathComponent(stem.type.canonicalStemFilename, isDirectory: false)
            if stem.url.standardizedFileURL != destination.standardizedFileURL {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: stem.url, to: destination)
            }
            return StemFile(type: stem.type, url: destination, displayName: stem.displayName)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(localMetadata)
            .write(to: directory.appendingPathComponent(Self.metadataFilename), options: .atomic)
        return localMetadata
    }

    func readStemMetadata(
        projectURL: URL,
        expectedFingerprint: StemSourceFingerprint?,
        fallbackFingerprint: StemSourceFingerprint? = nil
    ) throws -> StemCacheMetadata? {
        let directory = stemsDirectory(for: projectURL)
        let metadataURL = directory.appendingPathComponent(Self.metadataFilename)
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }

        let data = try Data(contentsOf: metadataURL)
        var metadata = try JSONDecoder().decode(StemCacheMetadata.self, from: data)

        if let expectedFingerprint {
            let matchesExpected = metadata.sourceFingerprint == expectedFingerprint
                || metadata.sourceFingerprint.hasSameFileIdentity(as: expectedFingerprint)
            let matchesFallback = fallbackFingerprint.map { metadata.sourceFingerprint == $0 } ?? false
            guard matchesExpected || matchesFallback else { return nil }
        }

        let stems = try discoverStems(in: directory)
        guard stems.count == StemType.allCases.count else { return nil }
        metadata.stems = stems
        return metadata
    }

    func persistVideoAudioIfNeeded(_ file: ImportedAudioFile, projectURL: URL) throws -> ImportedAudioFile {
        guard file.mediaKind == .video else { return file }
        let destination = videoAudioURL(for: projectURL)
        try fileManager.createDirectory(at: mediaDirectory(for: projectURL), withIntermediateDirectories: true)

        if file.url.standardizedFileURL != destination.standardizedFileURL {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: file.url, to: destination)
        }

        return ImportedAudioFile(
            url: destination,
            sourceMediaURL: file.sourceMediaURL,
            displayName: file.displayName,
            duration: file.duration,
            mediaKind: .video
        )
    }

    func videoAudioURL(for projectURL: URL) -> URL {
        mediaDirectory(for: projectURL).appendingPathComponent(Self.extractedVideoAudioFilename, isDirectory: false)
    }

    func existingVideoAudioURL(for projectURL: URL) -> URL? {
        let url = videoAudioURL(for: projectURL)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func mainPeakformURL(for projectURL: URL) -> URL {
        peaksDirectory(for: projectURL).appendingPathComponent(Self.mainPeakformFilename, isDirectory: false)
    }

    private func stemPeakformURL(for type: StemType, projectURL: URL) -> URL {
        peaksDirectory(for: projectURL)
            .appendingPathComponent("\(type.rawValue).peakform", isDirectory: false)
    }

    private func discoverStems(in directory: URL) throws -> [StemFile] {
        let files = (fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }) ?? []

        return StemType.allCases.compactMap { type in
            guard let url = files.first(where: { $0.lastPathComponent.lowercased() == type.canonicalStemFilename }) else {
                return nil
            }
            return StemFile(type: type, url: url, displayName: type.title)
        }
    }
}
