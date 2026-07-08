import AVFoundation
import XCTest
@testable import JammLab

final class AudioSampleConverterTests: XCTestCase {
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
