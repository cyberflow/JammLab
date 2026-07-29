@preconcurrency import AVFoundation
import Foundation

enum SecurityScopedResourceLeaseError: LocalizedError {
    case accessDenied(URL)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let url):
            return "JammLab cannot access \(url.lastPathComponent). Choose the file or project folder again."
        }
    }
}

final class SecurityScopedResourceLease {
    let url: URL
    private var hasAccess: Bool

    init(url: URL, requiresAccess: Bool) throws {
        self.url = url
        hasAccess = url.startAccessingSecurityScopedResource()
        if requiresAccess, !hasAccess {
            throw SecurityScopedResourceLeaseError.accessDenied(url)
        }
    }

    deinit {
        if hasAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum AudioPreparationKind: Equatable, Sendable {
    case importing
    case openingProject
    case switchingMode
}

enum AudioPreparationPhase: Equatable, Sendable {
    case idle
    case decoding
    case installing
    case cancelled
    case failed
}

struct AudioPreparationViewState: Equatable, Sendable {
    var kind: AudioPreparationKind?
    var phase: AudioPreparationPhase = .idle
    var progress: Double?
    var status = ""
    var pendingPlaybackMode: PlaybackMode?
    var isCancellable = false

    var isActive: Bool {
        phase == .decoding || phase == .installing
    }

    static let idle = AudioPreparationViewState()
}

struct AudioPreparationProgress: Equatable, Sendable {
    var completedUnitCount: Int
    var totalUnitCount: Int
    var status: String

    var fractionCompleted: Double? {
        guard totalUnitCount > 0 else { return nil }
        return min(1, max(0, Double(completedUnitCount) / Double(totalUnitCount)))
    }
}

struct AudioPreparationMemoryPolicy: Sendable {
    var maximumCandidateBytes: UInt64

    static var `default`: AudioPreparationMemoryPolicy {
        let quarterOfPhysicalMemory = ProcessInfo.processInfo.physicalMemory / 4
        return AudioPreparationMemoryPolicy(
            maximumCandidateBytes: min(2 * 1_024 * 1_024 * 1_024, quarterOfPhysicalMemory)
        )
    }

    func validate(frameCount: AVAudioFramePosition, channelCount: AVAudioChannelCount) throws {
        let frames = UInt64(max(0, frameCount))
        let channels = UInt64(max(1, channelCount))
        let finalPCMBytes = frames.multipliedReportingOverflow(by: channels * 4)
        let workingSetBytes = finalPCMBytes.partialValue.multipliedReportingOverflow(by: 2)
        guard !finalPCMBytes.overflow,
              !workingSetBytes.overflow,
              workingSetBytes.partialValue <= maximumCandidateBytes
        else {
            throw MultiTrackAudioPlayerError.preparationMemoryLimitExceeded(
                requiredBytes: workingSetBytes.partialValue,
                limitBytes: maximumCandidateBytes
            )
        }
    }
}

struct PreparedAudioTrack: @unchecked Sendable {
    var stemType: StemType?
    var buffer: AVAudioPCMBuffer
    var volume: Float
}

struct PreparedPlaybackAsset: @unchecked Sendable {
    enum Storage {
        case decoded(outputFormat: AVAudioFormat, tracks: [PreparedAudioTrack])
        case originalURL(URL)
        case stems([StemFile], StemMixState)
    }

    var storage: Storage
}

protocol AudioPlaybackPreparing: Sendable {
    func prepareOriginal(
        url: URL,
        volume: Float,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset

    func prepareStems(
        _ stems: [StemFile],
        mixState: StemMixState,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset
}

struct LegacyAudioPlaybackPreparer: AudioPlaybackPreparing {
    func prepareOriginal(
        url: URL,
        volume: Float,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        try Task.checkCancellation()
        progress(AudioPreparationProgress(completedUnitCount: 1, totalUnitCount: 1, status: "Audio ready"))
        return PreparedPlaybackAsset(storage: .originalURL(url))
    }

    func prepareStems(
        _ stems: [StemFile],
        mixState: StemMixState,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        try Task.checkCancellation()
        progress(AudioPreparationProgress(completedUnitCount: 1, totalUnitCount: 1, status: "Stems ready"))
        return PreparedPlaybackAsset(storage: .stems(stems, mixState))
    }
}

struct MultiTrackAudioPreparer: AudioPlaybackPreparing {
    var memoryPolicy: AudioPreparationMemoryPolicy = .default

    func prepareOriginal(
        url: URL,
        volume: Float,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        let memoryPolicy = memoryPolicy
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            progress(AudioPreparationProgress(completedUnitCount: 0, totalUnitCount: 1, status: "Decoding audio"))
            let file = try AVAudioFile(forReading: url)
            let outputFormat = try Self.renderFormat(for: file.processingFormat)
            try memoryPolicy.validate(frameCount: file.length, channelCount: outputFormat.channelCount)
            let buffer = try AudioFileBufferDecoder.decode(
                file: file,
                to: outputFormat,
                cancellationCheck: Task.checkCancellation
            )
            try Task.checkCancellation()
            progress(AudioPreparationProgress(completedUnitCount: 1, totalUnitCount: 1, status: "Audio decoded"))
            return PreparedPlaybackAsset(
                storage: .decoded(
                    outputFormat: outputFormat,
                    tracks: [PreparedAudioTrack(stemType: nil, buffer: buffer, volume: volume)]
                )
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    func prepareStems(
        _ stems: [StemFile],
        mixState: StemMixState,
        progress: @escaping @Sendable (AudioPreparationProgress) -> Void
    ) async throws -> PreparedPlaybackAsset {
        guard !stems.isEmpty else {
            throw MultiTrackAudioPlayerError.noStems
        }

        let memoryPolicy = memoryPolicy
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let firstFile = try AVAudioFile(forReading: stems[0].url)
            let outputFormat = try Self.renderFormat(for: firstFile.processingFormat)
            var preparedTracks: [PreparedAudioTrack] = []
            preparedTracks.reserveCapacity(stems.count)

            var estimatedFrames: AVAudioFramePosition = 0
            for stem in stems {
                try Task.checkCancellation()
                let file = try AVAudioFile(forReading: stem.url)
                estimatedFrames += file.length
            }
            try memoryPolicy.validate(frameCount: estimatedFrames, channelCount: outputFormat.channelCount)

            for (index, stem) in stems.enumerated() {
                try Task.checkCancellation()
                progress(AudioPreparationProgress(
                    completedUnitCount: index,
                    totalUnitCount: stems.count,
                    status: "Decoding \(stem.type.title)"
                ))
                let file = try AVAudioFile(forReading: stem.url)
                let buffer = try AudioFileBufferDecoder.decode(
                    file: file,
                    to: outputFormat,
                    cancellationCheck: Task.checkCancellation
                )
                preparedTracks.append(PreparedAudioTrack(
                    stemType: stem.type,
                    buffer: buffer,
                    volume: mixState.effectiveVolume(for: stem.type)
                ))
            }

            try Task.checkCancellation()
            progress(AudioPreparationProgress(
                completedUnitCount: stems.count,
                totalUnitCount: stems.count,
                status: "Stems decoded"
            ))
            return PreparedPlaybackAsset(storage: .decoded(outputFormat: outputFormat, tracks: preparedTracks))
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func renderFormat(for sourceFormat: AVAudioFormat) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        ) else {
            throw MultiTrackAudioPlayerError.unsupportedAudioFormat
        }
        return format
    }
}
