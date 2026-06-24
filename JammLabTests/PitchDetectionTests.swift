import AVFoundation
import XCTest
@testable import JammLab

final class PitchDetectionTests: XCTestCase {
    func testPitchDetectorDefaultsRemainTrackAnalysisOriented() {
        let detector = PitchDetector()

        XCTAssertEqual(detector.silenceThreshold, 0.01, accuracy: 0.000_001)
        XCTAssertEqual(detector.absoluteThreshold, 0.12, accuracy: 0.000_001)
        XCTAssertEqual(detector.fallbackThreshold, 0.35, accuracy: 0.000_001)
    }

    func testTunerPitchDetectorDetectsQuietSineIgnoredByDefaultDetector() throws {
        let samples = sineWave(frequency: 440, duration: 0.4, amplitude: 0.006)

        XCTAssertNil(PitchDetector().detect(samples: samples, sampleRate: 44_100))

        let result = try XCTUnwrap(PitchDetector.tunerDefault.detect(samples: samples, sampleRate: 44_100))
        XCTAssertEqual(result.noteName, "A")
        XCTAssertEqual(result.octave, 4)
    }

    func testTunerPitchDetectorStillIgnoresSilence() {
        let samples = Array(repeating: Float(0), count: 16_384)

        XCTAssertNil(PitchDetector.tunerDefault.detect(samples: samples, sampleRate: 44_100))
    }

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

    func testAudioSampleConverterReadsMonoFloatNonInterleavedBuffers() throws {
        let buffer = try makeFloatBuffer(samplesByChannel: [[0.25, -0.5, 0.75]], interleaved: false)

        XCTAssertEqual(AudioSampleConverter.monoFloatSamples(from: buffer), [0.25, -0.5, 0.75])
    }

    func testAudioSampleConverterDownmixesStereoFloatNonInterleavedBuffers() throws {
        let buffer = try makeFloatBuffer(
            samplesByChannel: [
                [0.2, 0.4, 0.6],
                [0.4, 0.2, -0.2]
            ],
            interleaved: false
        )

        assertSamples(AudioSampleConverter.monoFloatSamples(from: buffer), equal: [0.3, 0.3, 0.2])
    }

    func testAudioSampleConverterDownmixesStereoFloatInterleavedBuffers() throws {
        let buffer = try makeFloatBuffer(
            samplesByChannel: [
                [0.2, 0.4, 0.6],
                [0.4, 0.2, -0.2]
            ],
            interleaved: true
        )

        assertSamples(AudioSampleConverter.monoFloatSamples(from: buffer), equal: [0.3, 0.3, 0.2])
    }

    func testAudioSampleConverterReturnsEmptySamplesForEmptyBuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 0

        XCTAssertEqual(AudioSampleConverter.monoFloatSamples(from: buffer), [])
    }

    func testAudioSampleConverterRejectsUnsupportedPCMFormat() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 1

        XCTAssertNil(AudioSampleConverter.monoFloatSamples(from: buffer))
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

    private func assertSamples(
        _ actual: [Float]?,
        equal expected: [Float],
        accuracy: Float = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected samples, got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualSample, expectedSample) in zip(actual, expected) {
            XCTAssertEqual(actualSample, expectedSample, accuracy: accuracy, file: file, line: line)
        }
    }

    private func makeFloatBuffer(samplesByChannel: [[Float]], interleaved: Bool) throws -> AVAudioPCMBuffer {
        let channelCount = samplesByChannel.count
        XCTAssertGreaterThan(channelCount, 0)
        let frameCount = try XCTUnwrap(samplesByChannel.first?.count)
        XCTAssertTrue(samplesByChannel.allSatisfy { $0.count == frameCount })

        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: AVAudioChannelCount(channelCount),
            interleaved: interleaved
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ))
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if interleaved {
            let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let audioBuffer = try XCTUnwrap(audioBuffers.first)
            let data = try XCTUnwrap(audioBuffer.mData)
            let samples = data.bindMemory(to: Float.self, capacity: frameCount * channelCount)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    samples[frame * channelCount + channel] = samplesByChannel[channel][frame]
                }
            }
        } else {
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0..<channelCount {
                for frame in 0..<frameCount {
                    channels[channel][frame] = samplesByChannel[channel][frame]
                }
            }
        }

        return buffer
    }
}
