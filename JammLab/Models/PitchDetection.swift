import Foundation

struct PitchDetectionResult: Equatable {
    let frequencyHz: Double
    let midiNote: Int
    let noteName: String
    let octave: Int
    let centsOffset: Double
    let confidence: Double
    let rms: Double

    var displayNote: String {
        "\(noteName)\(octave)"
    }
}

struct PitchFrame: Equatable {
    let time: TimeInterval
    let duration: TimeInterval
    let result: PitchDetectionResult?
}

struct PitchDetectionWorkspace {
    fileprivate var difference: [Double] = []
    fileprivate var normalized: [Double] = []
}

struct PitchDetector {
    var referenceFrequency: Double = 440
    var minimumFrequency: Double = 27.00
    var maximumFrequency: Double = 4_186.01
    var silenceThreshold: Double = 0.01
    var absoluteThreshold: Double = 0.12
    var fallbackThreshold: Double = 0.35

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        var workspace = PitchDetectionWorkspace()
        return samples.withUnsafeBufferPointer { buffer in
            detect(samples: buffer, sampleRate: sampleRate, workspace: &workspace)
        }
    }

    func detect(
        samples: ArraySlice<Float>,
        sampleRate: Double,
        workspace: inout PitchDetectionWorkspace
    ) -> PitchDetectionResult? {
        var result: PitchDetectionResult?
        let usedContiguousStorage = samples.withContiguousStorageIfAvailable { buffer in
            result = detect(samples: buffer, sampleRate: sampleRate, workspace: &workspace)
            return true
        } ?? false

        if usedContiguousStorage {
            return result
        }

        return detect(samples: Array(samples), sampleRate: sampleRate)
    }

    private func detect(
        samples: UnsafeBufferPointer<Float>,
        sampleRate: Double,
        workspace: inout PitchDetectionWorkspace
    ) -> PitchDetectionResult? {
        guard sampleRate > 0, samples.count > 8 else { return nil }

        let rms = Self.rms(samples)
        guard rms >= silenceThreshold else { return nil }

        let tauMin = max(2, Int((sampleRate / maximumFrequency).rounded(.down)))
        let tauMax = min(samples.count - 2, Int((sampleRate / minimumFrequency).rounded(.up)))
        guard tauMax > tauMin, samples.count > tauMax + 2 else { return nil }

        yinDifference(samples: samples, tauMax: tauMax, workspace: &workspace)
        cumulativeMeanNormalizedDifference(workspace: &workspace)

        guard let tau = bestTau(cumulativeMean: workspace.normalized, tauMin: tauMin, tauMax: tauMax) else {
            return nil
        }

        let refinedTau = parabolicTau(cumulativeMean: workspace.normalized, tau: tau)
        guard refinedTau > 0 else { return nil }

        let frequency = sampleRate / refinedTau
        guard frequency >= minimumFrequency, frequency <= maximumFrequency else { return nil }

        let note = Self.note(for: frequency, referenceFrequency: referenceFrequency, noteNames: noteNames)
        let confidence = max(0, min(1, 1 - workspace.normalized[tau]))

        return PitchDetectionResult(
            frequencyHz: frequency,
            midiNote: note.midiNote,
            noteName: note.name,
            octave: note.octave,
            centsOffset: note.centsOffset,
            confidence: confidence,
            rms: rms
        )
    }

    static func rms(_ samples: [Float]) -> Double {
        samples.withUnsafeBufferPointer { rms($0) }
    }

    private static func rms(_ samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { partial, sample in
            let value = Double(sample)
            return partial + value * value
        }
        return sqrt(sum / Double(samples.count))
    }

    static func midiNote(for frequency: Double, referenceFrequency: Double = 440) -> Int {
        guard frequency > 0, referenceFrequency > 0 else { return 0 }
        return Int((69 + 12 * log2(frequency / referenceFrequency)).rounded())
    }

    static func frequency(for midiNote: Int, referenceFrequency: Double = 440) -> Double {
        referenceFrequency * pow(2, Double(midiNote - 69) / 12)
    }

    static func centsOffset(frequency: Double, midiNote: Int, referenceFrequency: Double = 440) -> Double {
        guard frequency > 0 else { return 0 }
        return 1_200 * log2(frequency / Self.frequency(for: midiNote, referenceFrequency: referenceFrequency))
    }

    private func yinDifference(
        samples: UnsafeBufferPointer<Float>,
        tauMax: Int,
        workspace: inout PitchDetectionWorkspace
    ) {
        workspace.difference.resize(to: tauMax + 1, repeating: 0)
        let count = samples.count

        for tau in 1...tauMax {
            var sum = 0.0
            let limit = count - tau
            for index in 0..<limit {
                let delta = Double(samples[index] - samples[index + tau])
                sum += delta * delta
            }
            workspace.difference[tau] = sum
        }
    }

    private func cumulativeMeanNormalizedDifference(workspace: inout PitchDetectionWorkspace) {
        workspace.normalized.resize(to: workspace.difference.count, repeating: 1)
        var runningSum = 0.0

        for tau in 1..<workspace.difference.count {
            runningSum += workspace.difference[tau]
            workspace.normalized[tau] = runningSum > 0 ? workspace.difference[tau] * Double(tau) / runningSum : 1
        }
    }

    private func bestTau(cumulativeMean: [Double], tauMin: Int, tauMax: Int) -> Int? {
        var tau = tauMin
        while tau <= tauMax {
            if cumulativeMean[tau] < absoluteThreshold {
                while tau + 1 <= tauMax, cumulativeMean[tau + 1] < cumulativeMean[tau] {
                    tau += 1
                }
                return tau
            }
            tau += 1
        }

        guard let fallback = (tauMin...tauMax).min(by: { cumulativeMean[$0] < cumulativeMean[$1] }),
              cumulativeMean[fallback] < fallbackThreshold
        else {
            return nil
        }

        return fallback
    }

    private func parabolicTau(cumulativeMean: [Double], tau: Int) -> Double {
        guard tau > 0, tau + 1 < cumulativeMean.count else { return Double(tau) }

        let left = cumulativeMean[tau - 1]
        let center = cumulativeMean[tau]
        let right = cumulativeMean[tau + 1]
        let denominator = left - 2 * center + right

        guard abs(denominator) > 0.000_001 else { return Double(tau) }
        return Double(tau) + 0.5 * (left - right) / denominator
    }

    private static func note(
        for frequency: Double,
        referenceFrequency: Double,
        noteNames: [String]
    ) -> (midiNote: Int, name: String, octave: Int, centsOffset: Double) {
        let midiNote = midiNote(for: frequency, referenceFrequency: referenceFrequency)
        let noteIndex = (midiNote % 12 + 12) % 12
        return (
            midiNote,
            noteNames[noteIndex],
            midiNote / 12 - 1,
            centsOffset(frequency: frequency, midiNote: midiNote, referenceFrequency: referenceFrequency)
        )
    }
}

private extension Array where Element == Double {
    mutating func resize(to count: Int, repeating value: Double) {
        if self.count == count {
            for index in indices {
                self[index] = value
            }
        } else {
            self = Array(repeating: value, count: count)
        }
    }
}
