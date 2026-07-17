import AVFoundation
import XCTest
@testable import JammLab

final class MultiTrackAudioPlayerConversionTests: XCTestCase {
    func testDecodeConvertsIntegerPCMWithoutTruncatingSamples() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("integer-pcm.caf")
        try writeIntegerPCMFile(to: url, duration: 0.5)

        let file = try AVAudioFile(forReading: url)
        let outputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        ))
        let buffer = try AudioFileBufferDecoder.decode(file: file, to: outputFormat)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])

        XCTAssertEqual(buffer.frameLength, AVAudioFrameCount(44_100 * 0.5))
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(samples[$0]) > 0.01 })
    }

    private func writeIntegerPCMFile(to url: URL, duration: TimeInterval) throws {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ))
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount

        let samples = try XCTUnwrap(buffer.int16ChannelData?[0])
        for frame in 0..<Int(frameCount) {
            samples[frame] = Int16(sin(Double(frame) * 0.05) * 8_000)
        }

        try file.write(from: buffer)
    }
}
