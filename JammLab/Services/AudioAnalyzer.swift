import AVFoundation
import Foundation

protocol AudioAnalyzing {
    func analyze(url: URL, includesTempo: Bool, includesKey: Bool) async throws -> AnalysisResult
}

extension AudioAnalyzing {
    func analyze(url: URL) async throws -> AnalysisResult {
        try await analyze(url: url, includesTempo: true, includesKey: true)
    }

    func analyze(url: URL, includesTempo: Bool) async throws -> AnalysisResult {
        try await analyze(url: url, includesTempo: includesTempo, includesKey: true)
    }
}

enum AudioAnalyzerError: LocalizedError {
    case unsupportedBuffer
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .unsupportedBuffer:
            return "Could not decode this file into a readable PCM buffer."
        case .emptyAudio:
            return "The audio file did not contain enough samples to analyze."
        }
    }
}

final class AudioAnalyzer: AudioAnalyzing {
    private let maximumAnalysisSeconds: Double = 90

    func analyze(url: URL, includesTempo: Bool, includesKey: Bool) async throws -> AnalysisResult {
        guard includesTempo || includesKey else {
            return AnalysisResult(bpm: nil, keyName: nil, keyConfidence: 0)
        }

        return try await Task.detached(priority: .userInitiated) {
            let audio = try self.loadMonoSamples(from: url)
            let bpm = includesTempo ? self.estimateBPM(samples: audio.samples, sampleRate: audio.sampleRate) : nil
            let key = includesKey ? self.estimateKey(samples: audio.samples, sampleRate: audio.sampleRate) : nil

            return AnalysisResult(
                bpm: bpm,
                keyName: key?.name,
                keyConfidence: key?.confidence ?? 0
            )
        }.value
    }

    private func loadMonoSamples(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let framesToRead = min(file.length, AVAudioFramePosition(format.sampleRate * maximumAnalysisSeconds))

        guard framesToRead > 0 else {
            throw AudioAnalyzerError.emptyAudio
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(framesToRead)
        ) else {
            throw AudioAnalyzerError.unsupportedBuffer
        }

        try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))

        guard let channels = buffer.floatChannelData else {
            throw AudioAnalyzerError.unsupportedBuffer
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = Array(repeating: Float(0), count: frameLength)

        for channel in 0..<channelCount {
            let data = channels[channel]
            for index in 0..<frameLength {
                mono[index] += data[index] / Float(channelCount)
            }
        }

        guard mono.contains(where: { abs($0) > 0.0001 }) else {
            throw AudioAnalyzerError.emptyAudio
        }

        return (mono, format.sampleRate)
    }

    private func estimateBPM(samples: [Float], sampleRate: Double) -> Int? {
        let hopSize = 1_024
        let frameSize = 2_048

        guard samples.count > frameSize * 4 else { return nil }

        var envelope: [Double] = []
        envelope.reserveCapacity(samples.count / hopSize)

        // MVP beat tracking: build a short-time RMS energy envelope. Peaks in this
        // envelope often line up with kick/snare hits, which is enough for a rough
        // practice-oriented tempo estimate but not a production-grade beat tracker.
        for start in stride(from: 0, to: samples.count - frameSize, by: hopSize) {
            var sum: Double = 0
            for index in start..<(start + frameSize) {
                let value = Double(samples[index])
                sum += value * value
            }
            envelope.append(sqrt(sum / Double(frameSize)))
        }

        guard envelope.count > 8 else { return nil }

        let mean = envelope.reduce(0, +) / Double(envelope.count)
        let centered = envelope.map { max(0, $0 - mean) }

        var bestBPM: Int?
        var bestScore = 0.0

        for bpm in 60...200 {
            let secondsPerBeat = 60.0 / Double(bpm)
            let lag = Int((secondsPerBeat * sampleRate / Double(hopSize)).rounded())

            guard lag > 1, lag < centered.count else { continue }

            var score = 0.0
            for index in lag..<centered.count {
                score += centered[index] * centered[index - lag]
            }

            if score > bestScore {
                bestScore = score
                bestBPM = bpm
            }
        }

        return bestBPM
    }

    private func estimateKey(samples: [Float], sampleRate: Double) -> (name: String?, confidence: Double) {
        let windowSize = 4_096
        let hopSize = 8_192
        let maximumWindows = 220

        guard samples.count > windowSize else {
            return (nil, 0)
        }

        var chroma = Array(repeating: 0.0, count: 12)
        var windowsUsed = 0

        // MVP key estimation: use Goertzel magnitudes for equal-tempered MIDI notes
        // and fold them into 12 pitch classes. This approximates a chromagram without
        // shipping a DSP dependency, and it can be replaced by Essentia/CoreML later.
        for start in stride(from: 0, to: samples.count - windowSize, by: hopSize) {
            if windowsUsed >= maximumWindows { break }

            for midiNote in 36...84 {
                let frequency = 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
                let magnitude = goertzelMagnitude(
                    samples: samples,
                    start: start,
                    count: windowSize,
                    sampleRate: sampleRate,
                    frequency: frequency
                )
                chroma[midiNote % 12] += magnitude
            }

            windowsUsed += 1
        }

        let totalEnergy = chroma.reduce(0, +)
        guard totalEnergy > 0 else {
            return (nil, 0)
        }

        let normalizedChroma = chroma.map { $0 / totalEnergy }
        return matchKeyProfile(chroma: normalizedChroma)
    }

    private func goertzelMagnitude(
        samples: [Float],
        start: Int,
        count: Int,
        sampleRate: Double,
        frequency: Double
    ) -> Double {
        let omega = 2.0 * .pi * frequency / sampleRate
        let coefficient = 2.0 * cos(omega)
        var previous = 0.0
        var previous2 = 0.0

        for index in start..<(start + count) {
            let sample = Double(samples[index])
            let value = sample + coefficient * previous - previous2
            previous2 = previous
            previous = value
        }

        return previous2 * previous2 + previous * previous - coefficient * previous * previous2
    }

    private func matchKeyProfile(chroma: [Double]) -> (name: String?, confidence: Double) {
        let pitchNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

        var scoredKeys: [(name: String, score: Double)] = []

        for root in 0..<12 {
            scoredKeys.append((
                "\(pitchNames[root]) major",
                correlation(chroma: chroma, profile: rotated(majorProfile, by: root))
            ))
            scoredKeys.append((
                "\(pitchNames[root]) minor",
                correlation(chroma: chroma, profile: rotated(minorProfile, by: root))
            ))
        }

        let sorted = scoredKeys.sorted { $0.score > $1.score }
        guard let best = sorted.first else { return (nil, 0) }

        let second = sorted.dropFirst().first?.score ?? 0
        let confidence = max(0, min(1, (best.score - second + 0.15) / 0.35))
        return (best.name, confidence)
    }

    private func rotated(_ values: [Double], by root: Int) -> [Double] {
        values.indices.map { values[($0 - root + values.count) % values.count] }
    }

    private func correlation(chroma: [Double], profile: [Double]) -> Double {
        let chromaMean = chroma.reduce(0, +) / Double(chroma.count)
        let profileMean = profile.reduce(0, +) / Double(profile.count)

        var numerator = 0.0
        var chromaDenominator = 0.0
        var profileDenominator = 0.0

        for index in chroma.indices {
            let x = chroma[index] - chromaMean
            let y = profile[index] - profileMean
            numerator += x * y
            chromaDenominator += x * x
            profileDenominator += y * y
        }

        let denominator = sqrt(chromaDenominator * profileDenominator)
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}
