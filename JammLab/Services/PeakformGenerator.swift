import AVFoundation
import Foundation

struct PeakformGenerator {
    let samplesPerPeakLevels: [Int]

    init(samplesPerPeakLevels: [Int] = PeakformData.defaultSamplesPerPeakLevels) {
        self.samplesPerPeakLevels = samplesPerPeakLevels
            .filter { $0 > 0 }
            .uniqued()
            .sorted()
    }

    func buildPeakform(from url: URL) throws -> PeakformData {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        guard file.length > 0 else {
            throw PeakformProviderError.emptyAudio
        }

        let frameCapacity: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw PeakformProviderError.unsupportedBuffer
        }

        let channelCount = Int(format.channelCount)
        var accumulators = samplesPerPeakLevels.map { samplesPerPeak in
            PeakformLevelAccumulator(
                samplesPerPeak: samplesPerPeak,
                estimatedFrameCount: Int(file.length)
            )
        }
        var hasSignal = false

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frameCapacity)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else {
                throw PeakformProviderError.unsupportedBuffer
            }

            for frame in 0..<frameLength {
                var mono = Float32(0)

                for channel in 0..<channelCount {
                    mono += channels[channel][frame] / Float32(channelCount)
                }

                if abs(mono) > 0.0001 {
                    hasSignal = true
                }

                for index in accumulators.indices {
                    accumulators[index].append(mono)
                }
            }
        }

        for index in accumulators.indices {
            accumulators[index].finish()
        }

        let levels = accumulators.map(\.level).filter { !$0.peaks.isEmpty }
        guard hasSignal, !levels.isEmpty else {
            throw PeakformProviderError.emptyAudio
        }

        return PeakformData(
            duration: Double(file.length) / format.sampleRate,
            sampleRate: format.sampleRate,
            levels: levels
        )
    }
}

private struct PeakformLevelAccumulator {
    let samplesPerPeak: Int
    private(set) var peaks: [PeakPoint] = []
    private var blockMin = Float32.greatestFiniteMagnitude
    private var blockMax = -Float32.greatestFiniteMagnitude
    private var blockSquareSum: Double = 0
    private var blockSampleCount = 0

    init(samplesPerPeak: Int, estimatedFrameCount: Int) {
        self.samplesPerPeak = samplesPerPeak
        peaks.reserveCapacity(max(1, estimatedFrameCount / samplesPerPeak))
    }

    mutating func append(_ sample: Float32) {
        blockMin = min(blockMin, sample)
        blockMax = max(blockMax, sample)
        blockSquareSum += Double(sample * sample)
        blockSampleCount += 1

        appendPeakIfNeeded()
    }

    mutating func finish() {
        appendPeakIfNeeded(force: true)
    }

    var level: PeakformLevel {
        PeakformLevel(samplesPerPeak: samplesPerPeak, peaks: peaks)
    }

    private mutating func appendPeakIfNeeded(force: Bool = false) {
        guard blockSampleCount == samplesPerPeak || (force && blockSampleCount > 0) else { return }

        let rms = Float32(sqrt(blockSquareSum / Double(blockSampleCount)))
        peaks.append(PeakPoint(min: blockMin, max: blockMax, rms: rms))

        blockMin = Float32.greatestFiniteMagnitude
        blockMax = -Float32.greatestFiniteMagnitude
        blockSquareSum = 0
        blockSampleCount = 0
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
