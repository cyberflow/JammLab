import CoreGraphics
import Foundation

struct PeakPoint: Equatable {
    let min: Float32
    let max: Float32
    let rms: Float32
}

struct PeakformLevel: Equatable {
    let samplesPerPeak: Int
    let peaks: [PeakPoint]
}

struct PeakformData: Equatable {
    static let defaultSamplesPerPeakLevels = [128, 256, 512, 1_024, 2_048, 4_096]

    let duration: TimeInterval
    let sampleRate: Double
    let levels: [PeakformLevel]

    var samplesPerPeak: Int {
        defaultLevel?.samplesPerPeak ?? levels.first?.samplesPerPeak ?? 0
    }

    var peaks: [PeakPoint] {
        defaultLevel?.peaks ?? levels.first?.peaks ?? []
    }

    func level(samplesPerPeak: Int) -> PeakformLevel? {
        levels.first { $0.samplesPerPeak == samplesPerPeak }
    }

    func preferredLevel(for viewport: TimelineViewport, width: CGFloat) -> PeakformLevel? {
        guard
            sampleRate > 0,
            viewport.visibleDuration > 0,
            width > 0,
            !levels.isEmpty
        else {
            return defaultLevel ?? levels.first
        }

        let visibleSamples = sampleRate * viewport.visibleDuration
        let targetPeakCount = max(Double(width) / 1.5, 1)
        let targetSamplesPerPeak = max(1, visibleSamples / targetPeakCount)

        return levels.min { lhs, rhs in
            abs(Double(lhs.samplesPerPeak) - targetSamplesPerPeak) < abs(Double(rhs.samplesPerPeak) - targetSamplesPerPeak)
        }
    }

    private var defaultLevel: PeakformLevel? {
        level(samplesPerPeak: 512)
    }
}

protocol PeakformProvider {
    var samplesPerPeakLevels: [Int] { get }
    func peakform(for url: URL) async throws -> PeakformData
    func removeCachedPeakform(for url: URL) async
}

extension PeakformProvider {
    func removeCachedPeakform(for url: URL) async {}
}

enum PeakformProviderError: LocalizedError, Equatable {
    case unsupportedBuffer
    case emptyAudio
    case invalidCache
    case unsupportedCacheVersion

    var errorDescription: String? {
        switch self {
        case .unsupportedBuffer:
            return "Could not decode this file into peakform data."
        case .emptyAudio:
            return "The audio file did not contain enough signal to draw a peakform."
        case .invalidCache:
            return "The peakform cache is invalid."
        case .unsupportedCacheVersion:
            return "The peakform cache version is not supported."
        }
    }
}
