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

struct PitchDetector {
    var referenceFrequency: Double = 440
    var minimumFrequency: Double = 27.00
    var maximumFrequency: Double = 4_186.01
    var silenceThreshold: Double = 0.01
    var absoluteThreshold: Double = 0.12
    var fallbackThreshold: Double = 0.35

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    func detect(samples: [Float], sampleRate: Double) -> PitchDetectionResult? {
        guard sampleRate > 0, samples.count > 8 else { return nil }

        let rms = Self.rms(samples)
        guard rms >= silenceThreshold else { return nil }

        let tauMin = max(2, Int((sampleRate / maximumFrequency).rounded(.down)))
        let tauMax = min(samples.count - 2, Int((sampleRate / minimumFrequency).rounded(.up)))
        guard tauMax > tauMin, samples.count > tauMax + 2 else { return nil }

        let difference = yinDifference(samples: samples, tauMax: tauMax)
        let cumulativeMean = cumulativeMeanNormalizedDifference(difference)

        guard let tau = bestTau(cumulativeMean: cumulativeMean, tauMin: tauMin, tauMax: tauMax) else {
            return nil
        }

        let refinedTau = parabolicTau(cumulativeMean: cumulativeMean, tau: tau)
        guard refinedTau > 0 else { return nil }

        let frequency = sampleRate / refinedTau
        guard frequency >= minimumFrequency, frequency <= maximumFrequency else { return nil }

        let note = Self.note(for: frequency, referenceFrequency: referenceFrequency, noteNames: noteNames)
        let confidence = max(0, min(1, 1 - cumulativeMean[tau]))

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

    private func yinDifference(samples: [Float], tauMax: Int) -> [Double] {
        var difference = Array(repeating: 0.0, count: tauMax + 1)
        let count = samples.count

        for tau in 1...tauMax {
            var sum = 0.0
            let limit = count - tau
            for index in 0..<limit {
                let delta = Double(samples[index] - samples[index + tau])
                sum += delta * delta
            }
            difference[tau] = sum
        }

        return difference
    }

    private func cumulativeMeanNormalizedDifference(_ difference: [Double]) -> [Double] {
        var normalized = Array(repeating: 1.0, count: difference.count)
        var runningSum = 0.0

        for tau in 1..<difference.count {
            runningSum += difference[tau]
            normalized[tau] = runningSum > 0 ? difference[tau] * Double(tau) / runningSum : 1
        }

        return normalized
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
