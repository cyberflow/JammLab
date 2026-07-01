import AVFoundation
import Foundation

enum TrackPitchAnalyzerError: LocalizedError {
    case unsupportedBuffer
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .unsupportedBuffer:
            return "Could not decode this file into a readable PCM buffer."
        case .emptyAudio:
            return "The audio file did not contain enough samples to analyze pitch."
        }
    }
}

struct TrackPitchAnalyzer {
    var detector = PitchDetector()
    var windowSize = 4_096
    var hopSize = 2_048
    var maximumAnalysisSeconds: Double?

    func analyze(url: URL) async throws -> [PitchFrame] {
        try await Task.detached(priority: .userInitiated) {
            let audio = try loadMonoSamples(from: url, maximumAnalysisSeconds: maximumAnalysisSeconds)
            guard audio.samples.count >= windowSize else {
                throw TrackPitchAnalyzerError.emptyAudio
            }

            var frames: [PitchFrame] = []
            frames.reserveCapacity(max(1, audio.samples.count / hopSize))
            var workspace = PitchDetectionWorkspace()

            for start in stride(from: 0, through: audio.samples.count - windowSize, by: hopSize) {
                let end = start + windowSize
                let result = detector.detect(
                    samples: audio.samples[start..<end],
                    sampleRate: audio.sampleRate,
                    workspace: &workspace
                )

                frames.append(PitchFrame(
                    time: Double(start) / audio.sampleRate,
                    duration: Double(windowSize) / audio.sampleRate,
                    result: result
                ))
            }

            return frames
        }.value
    }
}

private func loadMonoSamples(
    from url: URL,
    maximumAnalysisSeconds: Double?
) throws -> (samples: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let requestedFrames = maximumAnalysisSeconds.map {
        AVAudioFramePosition(format.sampleRate * max(0, $0))
    } ?? file.length
    let framesToRead = min(file.length, requestedFrames)

    guard framesToRead > 0 else {
        throw TrackPitchAnalyzerError.emptyAudio
    }

    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(framesToRead)
    ) else {
        throw TrackPitchAnalyzerError.unsupportedBuffer
    }

    try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))

    guard let mono = AudioSampleConverter.monoFloatSamples(from: buffer) else {
        throw TrackPitchAnalyzerError.unsupportedBuffer
    }
    guard mono.contains(where: { abs($0) > 0.0001 }) else {
        throw TrackPitchAnalyzerError.emptyAudio
    }

    return (mono, format.sampleRate)
}
