import AVFoundation
import XCTest
@testable import JammLab

final class PitchDetectionTests: XCTestCase {
    func testPitchDetectorDetectsA4() throws {
        let samples = sineWave(frequency: 440, duration: 0.2)
        let result = try XCTUnwrap(PitchDetector().detect(samples: samples, sampleRate: 44_100))

        XCTAssertEqual(result.noteName, "A")
        XCTAssertEqual(result.octave, 4)
        XCTAssertEqual(result.midiNote, 69)
        XCTAssertEqual(result.frequencyHz, 440, accuracy: 1.0)
        XCTAssertEqual(result.centsOffset, 0, accuracy: 3.0)
        XCTAssertGreaterThan(result.confidence, 0.85)
    }

    func testPitchDetectorDetectsFiveStringBassLowB() throws {
        let lowB = PitchDetector.frequency(for: 23)
        let samples = sineWave(frequency: lowB, duration: 0.3)
        let result = try XCTUnwrap(PitchDetector().detect(samples: samples, sampleRate: 44_100))

        XCTAssertEqual(result.noteName, "B")
        XCTAssertEqual(result.octave, 0)
        XCTAssertEqual(result.midiNote, 23)
        XCTAssertEqual(result.frequencyHz, lowB, accuracy: 1.0)
    }

    func testPitchDetectorDetectsA0WithTunerBufferSize() throws {
        let sampleRate = 44_100.0
        let tunerBufferSize = 16_384
        let samples = sineWave(frequency: 27.5, duration: Double(tunerBufferSize) / sampleRate)
        let result = try XCTUnwrap(PitchDetector().detect(samples: samples, sampleRate: sampleRate))

        XCTAssertEqual(result.noteName, "A")
        XCTAssertEqual(result.octave, 0)
        XCTAssertEqual(result.midiNote, 21)
        XCTAssertEqual(result.frequencyHz, 27.5, accuracy: 1.0)
    }

    func testPitchDetectorReportsDetunedCents() throws {
        let frequency = 440 * pow(2, 25.0 / 1_200.0)
        let samples = sineWave(frequency: frequency, duration: 0.2)
        let result = try XCTUnwrap(PitchDetector().detect(samples: samples, sampleRate: 44_100))

        XCTAssertEqual(result.noteName, "A")
        XCTAssertEqual(result.octave, 4)
        XCTAssertEqual(result.centsOffset, 25, accuracy: 4.0)
    }

    func testPitchDetectorIgnoresSilence() {
        let samples = Array(repeating: Float(0), count: 8_192)

        XCTAssertNil(PitchDetector().detect(samples: samples, sampleRate: 44_100))
    }

    func testPitchDetectorHonorsConfiguredRange() {
        let samples = sineWave(frequency: 1_000, duration: 0.2)
        let detector = PitchDetector(minimumFrequency: 40, maximumFrequency: 500)

        XCTAssertNil(detector.detect(samples: samples, sampleRate: 44_100))
    }

    func testPitchMappingHelpers() {
        XCTAssertEqual(PitchDetector.midiNote(for: 440), 69)
        XCTAssertEqual(PitchDetector.frequency(for: 69), 440, accuracy: 0.0001)
        XCTAssertEqual(PitchDetector.centsOffset(frequency: 440, midiNote: 69), 0, accuracy: 0.0001)

        let sharpFrequency = 440 * pow(2, 50.0 / 1_200.0)
        XCTAssertEqual(PitchDetector.centsOffset(frequency: sharpFrequency, midiNote: 69), 50, accuracy: 0.0001)
    }

    func testTrackPitchAnalyzerReturnsTimestampedFrames() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("a4.wav")
        try writeWAV(samples: sineWave(frequency: 440, duration: 0.25), sampleRate: 44_100, to: url)

        let analyzer = TrackPitchAnalyzer(windowSize: 2_048, hopSize: 1_024)
        let frames = try await analyzer.analyze(url: url)

        XCTAssertGreaterThan(frames.count, 4)
        XCTAssertEqual(frames[0].time, 0, accuracy: 0.0001)
        XCTAssertEqual(frames[1].time, 1_024.0 / 44_100.0, accuracy: 0.0001)
        XCTAssertEqual(frames[0].duration, 2_048.0 / 44_100.0, accuracy: 0.0001)

        let result = try XCTUnwrap(frames.first(where: { $0.result != nil })?.result)
        XCTAssertEqual(result.noteName, "A")
        XCTAssertEqual(result.octave, 4)
    }

    private func sineWave(
        frequency: Double,
        duration: Double,
        sampleRate: Double = 44_100,
        amplitude: Float = 0.5
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        return (0..<count).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            return amplitude * Float(sin(phase))
        }
    }

    private func writeWAV(samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount

        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in samples.indices {
            channel[index] = samples[index]
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
