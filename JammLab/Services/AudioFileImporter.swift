import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum AudioFileImporterError: LocalizedError {
    case unsupportedFile
    case unreadableDuration

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "Only local MP3/WAV audio files and MP4/MOV/M4V video files are supported."
        case .unreadableDuration:
            return "Could not read the duration of this audio file."
        }
    }
}

final class AudioFileImporter {
    private let videoAudioExtractor: VideoAudioExtractionService

    init(videoAudioExtractor: VideoAudioExtractionService = VideoAudioExtractionService()) {
        self.videoAudioExtractor = videoAudioExtractor
    }

    @MainActor
    func importFile() async throws -> ImportedAudioFile? {
        let panel = NSOpenPanel()
        panel.title = "Choose an audio or video file"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedContentTypes

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return try await importFile(from: url)
    }

    func importFile(from url: URL) async throws -> ImportedAudioFile {
        guard let mediaKind = mediaKind(for: url) else {
            throw AudioFileImporterError.unsupportedFile
        }

        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch mediaKind {
        case .audio:
            let duration = try await loadDuration(for: url)
            return ImportedAudioFile(url: url, displayName: url.lastPathComponent, duration: duration)
        case .video:
            let extractedAudioURL = try await videoAudioExtractor.extractedAudioURL(for: url)
            let duration = try await loadDuration(for: extractedAudioURL)
            return ImportedAudioFile(
                url: extractedAudioURL,
                sourceMediaURL: url,
                displayName: url.lastPathComponent,
                duration: duration,
                mediaKind: .video
            )
        }
    }

    func mediaKind(for url: URL) -> ImportedMediaKind? {
        let pathExtension = url.pathExtension.lowercased()

        if Self.supportedAudioExtensions.contains(pathExtension) {
            return .audio
        }

        if Self.supportedVideoExtensions.contains(pathExtension) {
            return .video
        }

        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        guard let contentType = values?.contentType else { return nil }

        if Self.supportedAudioTypes.contains(where: { contentType.conforms(to: $0) }) {
            return .audio
        }

        if Self.supportedVideoTypes.contains(where: { contentType.conforms(to: $0) }) {
            return .video
        }

        return nil
    }

    private func loadDuration(for url: URL) async throws -> TimeInterval {
        try Self.decodedDuration(for: url)
    }

    static func decodedDuration(for url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        let seconds = TimeInterval(file.length) / file.processingFormat.sampleRate

        guard seconds.isFinite, seconds > 0 else {
            throw AudioFileImporterError.unreadableDuration
        }

        return seconds
    }

    static let supportedAudioExtensions: Set<String> = ["mp3", "wav"]
    static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static let supportedAudioTypes: [UTType] = [
        .mp3,
        UTType(filenameExtension: "wav") ?? .audio
    ]

    static let supportedVideoTypes: [UTType] = [
        .mpeg4Movie,
        .quickTimeMovie,
        UTType(filenameExtension: "m4v") ?? .movie
    ]

    static var supportedContentTypes: [UTType] {
        supportedAudioTypes + supportedVideoTypes
    }
}
