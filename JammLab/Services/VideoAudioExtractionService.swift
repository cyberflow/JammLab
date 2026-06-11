import AVFoundation
import CryptoKit
import Foundation

enum VideoAudioExtractionError: LocalizedError {
    case noAudioTrack
    case unsupportedExport
    case exportFailed(String)
    case unreadableExtractedAudio

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "This video does not contain an audio track."
        case .unsupportedExport:
            return "This video audio track cannot be exported."
        case .exportFailed(let reason):
            return "Video audio extraction failed: \(reason)"
        case .unreadableExtractedAudio:
            return "Extracted video audio could not be read."
        }
    }
}

final class VideoAudioExtractionService {
    private let fileManager: FileManager
    private let applicationSupportDirectory: URL

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        if let applicationSupportDirectory {
            self.applicationSupportDirectory = applicationSupportDirectory
        } else {
            self.applicationSupportDirectory = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
    }

    func extractedAudioURL(for videoURL: URL) async throws -> URL {
        let mediaDirectory = cacheDirectory(for: videoURL)
        let audioURL = mediaDirectory.appendingPathComponent("audio.m4a")

        if fileManager.fileExists(atPath: audioURL.path), isReadableAudio(audioURL) {
            return audioURL
        }

        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: audioURL.path) {
            try fileManager.removeItem(at: audioURL)
        }

        try await exportM4A(from: videoURL, to: audioURL)

        guard isReadableAudio(audioURL) else {
            throw VideoAudioExtractionError.unreadableExtractedAudio
        }

        return audioURL
    }

    func cacheDirectory(for mediaURL: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("JammLab", isDirectory: true)
            .appendingPathComponent("MediaCache", isDirectory: true)
            .appendingPathComponent(Self.cacheKey(for: mediaURL), isDirectory: true)
    }

    static func cacheKey(for mediaURL: URL) -> String {
        let identity = mediaIdentity(for: mediaURL)
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func mediaIdentity(for mediaURL: URL) -> String {
        let values = try? mediaURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = values?.fileSize ?? 0
        let modificationTime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(mediaURL.path)|\(fileSize)|\(modificationTime)"
    }

    private func exportM4A(from videoURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw VideoAudioExtractionError.noAudioTrack
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoAudioExtractionError.unsupportedExport
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false
        let duration = try await asset.load(.duration)
        exportSession.timeRange = CMTimeRange(start: .zero, duration: duration)

        try await exportSession.export(to: outputURL, as: .m4a)
    }

    private func isReadableAudio(_ url: URL) -> Bool {
        (try? AudioFileImporter.decodedDuration(for: url)) != nil
    }
}
